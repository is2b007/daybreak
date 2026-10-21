require "test_helper"

class WeeksControllerTest < ActionController::TestCase
  setup do
    @user = users(:one)
    session[:user_id] = @user.id
  end

  test "the board is one Monday-to-Sunday week, never spilling into next week" do
    travel_to Time.zone.local(2026, 4, 9, 10) do # a Thursday
      get :show
      assert_response :success
      assert_match(/day_2026-04-06/, @response.body)
      assert_match(/day_2026-04-12/, @response.body)
      assert_no_match(/day_2026-04-05/, @response.body)
      assert_no_match(/day_2026-04-13/, @response.body)
      assert_match(/kanban__column--past/, @response.body)
    end
  end

  test "any date in a week opens that whole week" do
    get :show, params: { date: "2026-04-15" }
    assert_match(/day_2026-04-13/, @response.body)
    assert_match(/day_2026-04-19/, @response.body)
    assert_no_match(/day_2026-04-20/, @response.body)
  end
end
