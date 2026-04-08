class RefreshTokensJob < ApplicationJob
  queue_as :maintenance

  def perform
    # Refresh Basecamp tokens expiring within 2 days
    User.where("basecamp_token_expires_at < ?", 2.days.from_now)
        .where.not(basecamp_refresh_token: nil)
        .find_each do |user|
      begin
        data = BasecampClient.refresh_token(user.basecamp_refresh_token)
        user.update!(
          basecamp_access_token: data["access_token"],
          basecamp_token_expires_at: 2.weeks.from_now
        )
      rescue => e
        Rails.logger.error("Token refresh failed for user #{user.id}: #{e.message}")
      end
    end
  end
end
