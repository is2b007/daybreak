class BasecampAvatarsController < ApplicationController
  skip_before_action :require_onboarding!, only: [ :show, :person ]
  skip_before_action :load_right_panel_data, only: [ :show, :person ]
  skip_before_action :load_active_timer, only: [ :show, :person ]

  def show
    return head :not_found unless current_user.basecamp_avatar_url.present?

    url = User.normalize_stored_basecamp_avatar_url(
      current_user.basecamp_avatar_url,
      basecamp_account_id: current_user.basecamp_account_id
    )
    return head :not_found if url.blank?

    client = BasecampClient.new(current_user)
    body, content_type = client.fetch_avatar_binary(url)
    response.headers["Cache-Control"] = "private, max-age=3600"
    send_data body, type: content_type, disposition: "inline"
  rescue ArgumentError, BasecampClient::AuthError
    head :not_found
  rescue StandardError => e
    Rails.logger.warn(
      "BasecampAvatarsController#show user_id=#{current_user&.id} url=#{current_user&.basecamp_avatar_url&.truncate(80)}: #{e.class}: #{e.message}"
    )
    head :not_found
  end

  # GET /basecamp/avatar?u=… — anyone's photo (mentions, comment authors). The
  # client only fetches https Basecamp /people/…/avatar URLs, so this can't be
  # used to proxy anything else.
  def person
    body, content_type = BasecampClient.new(current_user).fetch_avatar_binary(params[:u].to_s)
    response.headers["Cache-Control"] = "private, max-age=86400"
    send_data body, type: content_type, disposition: "inline"
  rescue ArgumentError, BasecampClient::AuthError
    head :not_found
  rescue StandardError => e
    Rails.logger.warn("BasecampAvatarsController#person: #{e.class}: #{e.message}")
    head :not_found
  end
end
