require "test_helper"

class OnboardingControllerTest < ActionController::TestCase
  parallelize(workers: 1)

  setup do
    @user = users(:one)
    @user.update!(onboarded: false)
    session[:user_id] = @user.id
  end

  test "every step renders inside the sky with its own elevation" do
    (1..OnboardingController::STEPS).each do |step|
      get :show, params: { step: step }

      assert_response :success
      assert_select ".onb[data-controller=onboarding] turbo-frame#onboarding_step[data-turbo-action=advance]"
      assert_select "[data-onboarding-step='#{step}'][data-elevation]"
      assert_select ".onb__dot", OnboardingController::STEPS
    end
  end

  test "the sun only rises: each step sits higher than the one before" do
    elevations = (1..OnboardingController::STEPS).map do |step|
      get :show, params: { step: step }
      css_select("[data-onboarding-step]").first["data-elevation"].to_f
    end

    assert_equal elevations.sort, elevations
  end

  test "naming yourself moves on to the stamp" do
    patch :update, params: { step: 2, name: "Kosta" }

    assert_redirected_to onboarding_path(step: 3)
    assert_equal "Kosta", @user.reload.name
  end

  test "connecting HEY leaves the frame for the HEY flow" do
    get :show, params: { step: 5 }

    assert_select "a[href='#{auth_hey_path}'][data-turbo-frame=_top]"
  end

  test "the last step finishes onboarding" do
    patch :update, params: { step: 7 }

    assert_redirected_to root_path
    assert @user.reload.onboarded?
    assert flash[:arrival], "the week should fade in out of the morning sky"
  end
end
