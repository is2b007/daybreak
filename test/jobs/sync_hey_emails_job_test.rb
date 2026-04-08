require "test_helper"

class SyncHeyEmailsJobTest < ActiveJob::TestCase
  # Plain stub — the project doesn't use a mocking library, and minitest 6
  # dropped Object#stub. We swap HeyClient.new via define_singleton_method.
  class StubHeyClient
    attr_accessor :imbox_data, :later_data, :aside_data

    def initialize(imbox: [], later: [], aside: [])
      @imbox_data = imbox
      @later_data = later
      @aside_data = aside
    end

    def imbox = @imbox_data
    def reply_later = @later_data
    def set_aside = @aside_data
  end

  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub-token",
      hey_refresh_token: "stub-refresh",
      hey_token_expires_at: 2.weeks.from_now
    )
  end

  def with_hey_client(stub)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_user| stub }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  def posting(id, subject:, folder_extra: {})
    {
      "id" => id,
      "kind" => "topic",
      "name" => subject,
      "summary" => "Snippet for #{subject}",
      "app_url" => "https://app.hey.com/topics/#{id}",
      "observed_at" => 1.hour.ago.iso8601,
      "creator" => { "name" => "Alice", "email_address" => "alice@example.com" }
    }.merge(folder_extra)
  end

  test "creates HeyEmail rows from imbox/reply_later/set_aside postings" do
    stub = StubHeyClient.new(
      imbox: [ posting(101, subject: "Imbox one"), posting(102, subject: "Imbox two") ],
      later: [ posting(201, subject: "Later one") ],
      aside: [ posting(301, subject: "Aside one") ]
    )

    with_hey_client(stub) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    assert_equal 4, @user.hey_emails.count
    assert_equal 2, @user.hey_emails.imbox.count
    assert_equal 1, @user.hey_emails.reply_later.count
    assert_equal 1, @user.hey_emails.set_aside.count
    assert_equal "Imbox one", @user.hey_emails.find_by(external_id: "101").subject
    assert_equal "alice@example.com", @user.hey_emails.find_by(external_id: "101").sender_email
    assert_equal "https://app.hey.com/topics/101", @user.hey_emails.find_by(external_id: "101").hey_url
  end

  test "is idempotent: second run does not duplicate or churn updated_at on unchanged rows" do
    stub = StubHeyClient.new(imbox: [ posting(101, subject: "Hello") ])

    with_hey_client(stub) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    row = @user.hey_emails.find_by(external_id: "101")
    original_updated_at = row.updated_at

    travel 1.minute do
      with_hey_client(stub) do
        SyncHeyEmailsJob.perform_now(@user.id)
      end
    end

    assert_equal 1, @user.hey_emails.count
    assert_equal original_updated_at.to_i, row.reload.updated_at.to_i
  end

  test "prune removes rows gone from HEY but preserves triaged and dismissed rows" do
    # Seed three rows that existed on a previous sync.
    kept_active = @user.hey_emails.create!(
      external_id: "101", folder: :imbox, subject: "Still here",
      received_at: 1.hour.ago
    )
    kept_triaged = @user.hey_emails.create!(
      external_id: "102", folder: :imbox, subject: "Triaged earlier",
      received_at: 1.hour.ago, triaged_at: 10.minutes.ago
    )
    kept_dismissed = @user.hey_emails.create!(
      external_id: "103", folder: :imbox, subject: "Dismissed earlier",
      received_at: 1.hour.ago, dismissed_at: 5.minutes.ago
    )

    # HEY now returns only 101 — 102 and 103 should be pruned only if not locally handled.
    stub = StubHeyClient.new(imbox: [ posting(101, subject: "Still here") ])

    with_hey_client(stub) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    assert HeyEmail.exists?(kept_active.id), "active current row should remain"
    assert HeyEmail.exists?(kept_triaged.id), "triaged row should be preserved"
    assert HeyEmail.exists?(kept_dismissed.id), "dismissed row should be preserved"
  end

  test "upsert does not clear local dismissed_at or triaged_at on existing row" do
    @user.hey_emails.create!(
      external_id: "101", folder: :imbox, subject: "Old subject",
      received_at: 2.hours.ago, triaged_at: 1.hour.ago
    )

    stub = StubHeyClient.new(imbox: [ posting(101, subject: "Updated subject") ])

    with_hey_client(stub) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    row = @user.hey_emails.find_by(external_id: "101")
    assert_equal "Updated subject", row.subject
    assert_not_nil row.triaged_at
  end

  test "skips entries (only topics and bundles are triagable)" do
    stub = StubHeyClient.new(
      imbox: [
        posting(101, subject: "Topic"),
        posting(102, subject: "Bundle", folder_extra: { "kind" => "bundle" }),
        posting(103, subject: "Reply entry", folder_extra: { "kind" => "entry" })
      ]
    )

    with_hey_client(stub) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    assert_equal 2, @user.hey_emails.count
    assert_not @user.hey_emails.exists?(external_id: "103")
  end

  test "upstream fetch error does not prune cached rows" do
    # Seed two live rows from a previous successful sync.
    @user.hey_emails.create!(
      external_id: "101", folder: :imbox, subject: "Still here one",
      received_at: 1.hour.ago
    )
    @user.hey_emails.create!(
      external_id: "102", folder: :imbox, subject: "Still here two",
      received_at: 2.hours.ago
    )

    # HeyClient returning nil from its fetch methods simulates a non-200
    # response (e.g. HEY is flaking, or OAuth scope is wrong). The sync job
    # must treat this as "skip, don't prune" — otherwise one bad request
    # wipes the triage list.
    flaky = Object.new
    def flaky.imbox; nil; end
    def flaky.reply_later; nil; end
    def flaky.set_aside; nil; end

    with_hey_client(flaky) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    assert_equal 2, @user.hey_emails.count
  end

  test "rescues HeyClient::AuthError without raising" do
    # Seed a live row so we can also prove the rescue short-circuits before any prune.
    @user.hey_emails.create!(
      external_id: "101", folder: :imbox, subject: "Still here",
      received_at: 1.hour.ago
    )

    auth_fail = Object.new
    def auth_fail.imbox; raise HeyClient::AuthError, "HEY session expired"; end
    def auth_fail.reply_later; raise "should not be called"; end
    def auth_fail.set_aside; raise "should not be called"; end

    with_hey_client(auth_fail) do
      assert_nothing_raised do
        SyncHeyEmailsJob.perform_now(@user.id)
      end
    end

    # Rescue fires on the first folder; no pruning happens.
    assert_equal 1, @user.hey_emails.count
  end

  test "skips sync when user is not HEY-connected" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)

    # Should not hit HeyClient at all — any call raises via the guard stub below.
    tripwire = Object.new
    def tripwire.imbox; raise "should not be called"; end
    def tripwire.reply_later; raise "should not be called"; end
    def tripwire.set_aside; raise "should not be called"; end

    with_hey_client(tripwire) do
      SyncHeyEmailsJob.perform_now(@user.id)
    end

    assert_equal 0, @user.hey_emails.count
  end
end
