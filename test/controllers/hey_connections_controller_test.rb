require "test_helper"

class HeyConnectionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "new explains pasted CLI tokens cannot refresh" do
    get :new

    assert_response :success
    assert_match(/cannot refresh/i, response.body)
    assert_match(/two weeks/i, response.body)
  end
end
