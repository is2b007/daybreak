class RefreshTokensJob < ApplicationJob
  queue_as :maintenance

  def perform
    refresh_basecamp_tokens
    refresh_hey_tokens
  end

  private

  def refresh_basecamp_tokens
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
        Rails.logger.error("Basecamp token refresh failed for user #{user.id}: #{e.message}")
      end
    end
  end

  def refresh_hey_tokens
    User.where("hey_token_expires_at < ?", 2.days.from_now)
        .where.not(hey_refresh_token: nil)
        .find_each do |user|
      begin
        data = HeyClient.refresh_token(user.hey_refresh_token)
        user.update!(
          hey_access_token: data["access_token"],
          hey_token_expires_at: 2.weeks.from_now
        )
      rescue => e
        Rails.logger.error("HEY token refresh failed for user #{user.id}: #{e.message}")
      end
    end
  end
end
