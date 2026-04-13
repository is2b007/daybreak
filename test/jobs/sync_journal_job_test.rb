require "test_helper"

class SyncJournalJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    @date = Date.new(2026, 4, 10)
  end

  def with_hey_client(client)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| client }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "writes scratchpad plain text first then day log section" do
    @user.local_journal_entries.create!(
      date: @date,
      content: "<p>Scratch <strong>line</strong></p>"
    )
    @user.daily_logs.create!(date: @date).tap do |log|
      log.log_entries.create!(content: "Logged item", logged_at: Time.zone.parse("2026-04-10 09:00"))
    end

    captured = nil
    client = Object.new
    client.define_singleton_method(:write_journal) do |day, body|
      captured = [ day, body ]
      { "id" => "1" }
    end

    with_hey_client(client) do
      SyncJournalJob.perform_now(@user.id, @date.to_s)
    end

    assert captured
    assert_equal @date.to_s, captured[0]
    assert_match(/\AScratch line\n\n---\nDay log\n\n/m, captured[1])

    row = @user.local_journal_entries.find_by(date: @date)
    assert_equal row.content_digest, row.reload.last_pushed_to_hey_digest
  end

  test "marks digest when write_journal returns empty hash (HEY empty body)" do
    @user.local_journal_entries.create!(
      date: @date,
      content: "<p>Only scratch</p>"
    )

    client = Object.new
    client.define_singleton_method(:write_journal) { |_, _| {} }

    with_hey_client(client) do
      SyncJournalJob.perform_now(@user.id, @date.to_s)
    end

    row = @user.local_journal_entries.find_by(date: @date)
    assert_equal row.content_digest, row.reload.last_pushed_to_hey_digest
  end

  test "skips when not HEY connected" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)
    called = false
    client = Object.new
    client.define_singleton_method(:write_journal) { |*, **| called = true }

    with_hey_client(client) do
      SyncJournalJob.perform_now(@user.id, @date.to_s)
    end

    assert_equal false, called
  end
end
