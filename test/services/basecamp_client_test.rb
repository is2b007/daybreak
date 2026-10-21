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

  test "upcoming_schedule asks Basecamp for the window and keys occurrences by day" do
    client = BasecampClient.new(users(:one))
    asked = nil
    report = {
      "schedule_entries" => [ { "id" => 4, "summary" => "Offsite", "starts_at" => "2026-11-03T10:00:00Z" } ],
      "recurring_schedule_entry_occurrences" => [
        {
          "id" => 10,
          "summary" => "Weekly sync",
          "recurring" => true,
          "starts_at" => "2026-11-02T09:00:00.000-05:00",
          "app_url" => "https://3.basecamp.com/1/buckets/2/schedule_entries/10/occurrences/20261102"
        },
        { "id" => 10, "summary" => "Weekly sync", "recurring" => true, "starts_at" => "2026-11-09T09:00:00.000-06:00" }
      ],
      "assignables" => []
    }
    client.define_singleton_method(:get) { |path, params = {}| asked = [ path, params ]; report }

    rows = client.upcoming_schedule(starts_on: Date.new(2026, 11, 2), ends_on: Date.new(2026, 11, 9))

    assert_equal "/reports/schedules/upcoming.json", asked[0]
    assert_equal({ window_starts_on: "2026-11-02", window_ends_on: "2026-11-09" }, asked[1])
    assert_equal [ 4, "10:2026-11-02", "10:2026-11-09" ], rows.map { |r| r["id"] }
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

  test "complete_card moves the card into its table's Done column" do
    client = BasecampClient.new(users(:one))
    pages = {
      "/card_tables/cards/77.json" => { "id" => 77, "completed" => false, "parent" => { "id" => 30, "type" => "Kanban::Column" } },
      "/card_tables/columns/30.json" => { "id" => 30, "parent" => { "id" => 20 } },
      "/card_tables/20.json" => { "id" => 20, "lists" => [ { "id" => 30, "type" => "Kanban::Column" }, { "id" => 31, "type" => "Kanban::DoneColumn" } ] }
    }
    moved = nil
    client.define_singleton_method(:get) { |path, _params = {}| pages.fetch(path) }
    client.define_singleton_method(:post) { |path, body| moved = [ path, body ] }

    client.complete_card(77)

    assert_equal [ "/card_tables/cards/77/moves.json", { column_id: 31 } ], moved
  end

  test "complete_card leaves a card already in Done alone" do
    client = BasecampClient.new(users(:one))
    client.define_singleton_method(:get) { |_path, _params = {}| { "id" => 77, "parent" => { "id" => 31, "type" => "Kanban::DoneColumn" } } }
    client.define_singleton_method(:post) { |*| flunk "should not move" }

    assert_nil client.complete_card(77)
  end
end
