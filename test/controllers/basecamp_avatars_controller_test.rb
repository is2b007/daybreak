require "test_helper"

class BasecampAvatarsControllerTest < ActionController::TestCase
  tests BasecampAvatarsController

  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "show returns not found when user has no stored avatar url" do
    @user.update_column(:basecamp_avatar_url, nil)
    get :show
    assert_response :not_found
  end
end
