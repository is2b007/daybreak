require "test_helper"

class SyncControllerTest < ActionController::TestCase
  tests SyncController

  class StubHeyClient
    def imbox = []
    def reply_later = []
    def set_aside = []
    def feed = []
    def paper_trail = []
  end

  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  def with_hey_client(stub)
    original = HeyClient.method(:new)
    HeyClient.define_singleton_method(:new) { |_user| stub }
    yield
  ensure
    HeyClient.define_singleton_method(:new, original)
  end

  test "hey redirects with alert when HEY is not connected" do
    @user.update!(hey_access_token: nil, hey_refresh_token: nil, hey_token_expires_at: nil)
    post :hey
    assert_redirected_to root_path
    assert_equal "Connect HEY in Settings to sync.", flash[:alert]
  end

  test "hey redirects with notice when HEY is connected" do
    @user.update!(
      hey_access_token: "stub",
      hey_refresh_token: "stub-r",
      hey_token_expires_at: 2.weeks.from_now
    )

    with_hey_client(StubHeyClient.new) do
      post :hey
    end

    assert_redirected_to root_path
    assert_equal "HEY inbox updated.", flash[:notice]
  end
end
