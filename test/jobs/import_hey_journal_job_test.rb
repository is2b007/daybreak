require "test_helper"

class ImportHeyJournalJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )
    @date = Date.new(2026, 4, 11)
  end

  def with_hey_client(client)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_u| client }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "creates local entry from HEY plain text when empty" do
    client = Object.new
    client.define_singleton_method(:journal_entry) do |_day|
      { "content" => "Hello from HEY\n\nSecond paragraph" }
    end

    with_hey_client(client) do
      ImportHeyJournalJob.perform_now(@user.id, @date.to_s)
    end

    row = @user.local_journal_entries.find_by(date: @date)
    assert row
    assert_includes row.content, "Hello from HEY"
    assert_equal row.content_digest, row.last_pushed_to_hey_digest
  end

  test "does not overwrite local scratchpad with content never pushed to HEY" do
    @user.local_journal_entries.create!(
      date: @date,
      content: "<p>Local only</p>",
      last_pushed_to_hey_digest: nil
    )

    client = Object.new
    client.define_singleton_method(:journal_entry) do |_day|
      { "content" => "Remote" }
    end

    with_hey_client(client) do
      ImportHeyJournalJob.perform_now(@user.id, @date.to_s)
    end

    row = @user.local_journal_entries.find_by(date: @date)
    assert_includes row.content, "Local only"
  end

  test "updates when local matches last pushed digest and HEY changed" do
    html = "<p>Synced</p>"
    digest = Digest::SHA256.hexdigest(html)
    @user.local_journal_entries.create!(
      date: @date,
      content: html,
      last_pushed_to_hey_digest: digest
    )

    client = Object.new
    client.define_singleton_method(:journal_entry) do |_day|
      { "content" => "New from HEY" }
    end

    with_hey_client(client) do
      ImportHeyJournalJob.perform_now(@user.id, @date.to_s)
    end

    row = @user.local_journal_entries.find_by(date: @date)
    assert_includes row.content, "New from HEY"
  end
end
