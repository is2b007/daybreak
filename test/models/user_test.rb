require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalize_stored_basecamp_avatar_url expands relative API paths" do
    out = User.normalize_stored_basecamp_avatar_url(
      "/people/BAhpB--x/avatar",
      basecamp_account_id: "195539477"
    )
    assert_equal "https://3.basecampapi.com/195539477/people/BAhpB--x/avatar", out
  end

  test "normalize_stored_basecamp_avatar_url upgrades http to https" do
    out = User.normalize_stored_basecamp_avatar_url(
      "http://3.basecampapi.com/1/people/x/avatar",
      basecamp_account_id: "1"
    )
    assert_equal "https://3.basecampapi.com/1/people/x/avatar", out
  end

  test "extract_basecamp_avatar_url_from_profile reads top-level or nested keys" do
    assert_equal "https://x/a", User.extract_basecamp_avatar_url_from_profile({ "avatar_url" => "https://x/a" })
    assert_equal "https://x/b", User.extract_basecamp_avatar_url_from_profile({ "person" => { "avatar_url" => "https://x/b" } })
  end
end
