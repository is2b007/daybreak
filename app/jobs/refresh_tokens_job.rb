class RefreshTokensJob < ApplicationJob
  queue_as :maintenance

  REFRESH_WINDOW = 2.days

  def perform
    refresh_basecamp_tokens
    refresh_hey_tokens
  end

  private

  # Both refreshes go through the clients' locked path, so this job cannot race a sync
  # that is refreshing the same user and spend a rotated refresh token twice.
  def refresh_basecamp_tokens
    User.where("basecamp_token_expires_at < ?", REFRESH_WINDOW.from_now)
        .where.not(basecamp_refresh_token: nil)
        .find_each do |user|
      begin
        BasecampClient.new(user).refresh_access_token!(fresh_until: REFRESH_WINDOW.from_now)
      rescue => e
        Rails.logger.error("Basecamp token refresh failed for user #{user.id}: #{e.message}")
      end
    end
  end

  def refresh_hey_tokens
    User.where("hey_token_expires_at < ?", REFRESH_WINDOW.from_now)
        .where.not(hey_refresh_token: nil)
        .find_each do |user|
      begin
        HeyClient.new(user).refresh_access_token!(fresh_until: REFRESH_WINDOW.from_now)
      rescue => e
        Rails.logger.error("HEY token refresh failed for user #{user.id}: #{e.message}")
      end
    end
  end
end
