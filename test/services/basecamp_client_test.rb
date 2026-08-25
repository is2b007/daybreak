require "test_helper"

class BasecampClientTest < ActiveSupport::TestCase
  test "validate_basecamp_avatar_url! accepts Basecamp static CDN avatar URLs" do
    user = users(:one)
    client = BasecampClient.new(user)
    url = "https://bc3-production-assets-cdn.basecamp-static.com/577/people/BAhpBEzV1QI=--x/avatar"
    assert_nothing_raised { client.send(:validate_basecamp_avatar_url!, url) }
  end

  test "validate_basecamp_avatar_url! rejects non-Basecamp hosts even with avatar-shaped path" do
    user = users(:one)
    client = BasecampClient.new(user)
    url = "https://evil.example/1/people/x/avatar"
    assert_raises(ArgumentError) { client.send(:validate_basecamp_avatar_url!, url) }
  end

  test "normalize_my_assignments_payload flattens priorities and non_priorities" do
    user = users(:one)
    client = BasecampClient.new(user)

    payload = {
      "priorities" => [
        {
          "id" => 101,
          "type" => "todo",
          "content" => "Priority",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "Project A" }
        }
      ],
      "non_priorities" => [
        {
          "id" => 102,
          "type" => "todo",
          "content" => "Later",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "Project A" }
        }
      ]
    }

    list = client.send(:normalize_my_assignments_payload, payload)
    assert_equal 2, list.size
    assert_equal [ 101, 102 ], list.map { |a| a["id"] }
  end

  test "normalize_my_assignments_payload includes nested todo children" do
    user = users(:one)
    client = BasecampClient.new(user)

    payload = {
      "priorities" => [],
      "non_priorities" => [
        {
          "id" => 200,
          "type" => "todo",
          "content" => "Parent",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "P" },
          "children" => [
            {
              "id" => 201,
              "type" => "todo",
              "content" => "Child step",
              "completed" => false,
              "bucket" => { "id" => 1, "name" => "P" }
            }
          ]
        }
      ]
    }

    list = client.send(:normalize_my_assignments_payload, payload)
    assert_equal 2, list.size
    assert_includes list.map { |a| a["id"] }, 201
  end

  test "complete_todo and uncomplete_todo use flat completion routes" do
    client = BasecampClient.new(users(:one))
    posted = deleted = nil
    client.define_singleton_method(:post) { |path, _body = nil| posted = path }
    client.define_singleton_method(:delete) { |path| deleted = path }

    client.complete_todo("2085958505", "99")
    client.uncomplete_todo("2085958505", "99")

    assert_equal "/todos/99/completion.json", posted
    assert_equal "/todos/99/completion.json", deleted
  end

  test "comments and create_comment use flat recording routes" do
    client = BasecampClient.new(users(:one))
    listed = created = nil
    client.define_singleton_method(:get_paginated) { |path, _params = {}| listed = path; [] }
    client.define_singleton_method(:post) { |path, body = nil| created = [ path, body ] }

    client.comments("2085958505", "55")
    client.create_comment("2085958505", "55", content: "Nice")

    assert_equal "/recordings/55/comments.json", listed
    assert_equal "/recordings/55/comments.json", created[0]
    assert_equal "<div>Nice</div>", created[1][:content]
  end

  test "create_comment wraps plain text as official rich-text HTML" do
    client = BasecampClient.new(users(:one))
    body = nil
    client.define_singleton_method(:post) { |_path, payload| body = payload }

    client.create_comment("1", "2", content: "Line one\nLine two & more")

    assert_equal "<div>Line one<br>Line two &amp; more</div>", body[:content]
  end

  test "schedule_entries paginates the official flat list" do
    client = BasecampClient.new(users(:one))
    path = nil
    client.define_singleton_method(:get_paginated) { |p, _params = {}| path = p; [] }

    client.schedule_entries("12")
    assert_equal "/schedules/12/entries.json", path
  end

  test "pick_account prefers product bc3 then href then resource" do
    href_only = {
      "id" => 2,
      "href" => "https://3.basecampapi.com/2",
      "resource" => "urn:bc:account:2"
    }
    bc3 = { "id" => 1, "product" => "bc3", "href" => "https://3.basecampapi.com/1" }

    assert_equal 1, BasecampClient.pick_account([ href_only, bc3 ])["id"]
    assert_equal 2, BasecampClient.pick_account([ href_only ])["id"]
    assert_equal "2", BasecampClient.account_id_from(href_only)
    assert_equal "9", BasecampClient.account_id_from(
      "href" => "https://3.basecampapi.com/9",
      "resource" => "urn:bc:account:9"
    )
  end

  test "expires_at_from_token uses expires_in seconds" do
    travel_to Time.utc(2026, 4, 13, 12, 0, 0) do
      at = BasecampClient.expires_at_from_token("expires_in" => 1209600)
      assert_equal Time.utc(2026, 4, 27, 12, 0, 0), at
    end
  end

  test "persist_tokens! stores rotated refresh token" do
    user = users(:one)
    user.update!(
      basecamp_access_token: "old",
      basecamp_refresh_token: "old-r",
      basecamp_token_expires_at: 1.day.from_now
    )

    BasecampClient.persist_tokens!(user, {
      "access_token" => "new",
      "refresh_token" => "new-r",
      "expires_in" => 3600
    })
    user.reload

    assert_equal "new", user.basecamp_access_token
    assert_equal "new-r", user.basecamp_refresh_token
    assert user.basecamp_token_expires_at > 50.minutes.from_now
  end

  test "safe_next_page_uri only follows same-account basecampapi hosts" do
    user = users(:one)
    user.update_column(:basecamp_account_id, "195539477")
    client = BasecampClient.new(user)

    ok = "https://3.basecampapi.com/195539477/projects.json?page=2"
    assert_equal URI(ok), client.send(:safe_next_page_uri, ok)
    assert_nil client.send(:safe_next_page_uri, "https://evil.example/195539477/projects.json")
    assert_nil client.send(:safe_next_page_uri, "https://3.basecampapi.com/999/projects.json")
  end

  test "expand_schedule_entry_for_range expands weekly meetings into the window" do
    client = BasecampClient.new(users(:one))
    week = Date.new(2026, 4, 13)..Date.new(2026, 4, 19)
    entry = {
      "id" => 10,
      "summary" => "Weekly sync",
      "starts_at" => "2026-03-18T15:00:00Z",
      "ends_at" => "2026-03-18T16:00:00Z",
      "recurrence_schedule" => { "frequency" => "every_week", "start_date" => "2026-03-18" }
    }

    rows = client.send(:expand_schedule_entry_for_range, entry, week)
    assert_equal [ "10:2026-04-15" ], rows.map { |r| r["id"] }
    assert_equal "2026-04-15T15:00:00.000Z", Time.parse(rows.first["starts_at"]).utc.iso8601(3)
  end

  test "expand_schedule_entry_for_range leaves one-off entries unchanged" do
    client = BasecampClient.new(users(:one))
    week = Date.new(2026, 4, 13)..Date.new(2026, 4, 19)
    entry = { "id" => 4, "starts_at" => "2026-04-14T10:00:00Z", "ends_at" => "2026-04-14T11:00:00Z" }

    assert_equal [ entry ], client.send(:expand_schedule_entry_for_range, entry, week)
  end
end
