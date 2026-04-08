require "test_helper"

class HeyEmailTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "for_triage scope excludes dismissed and triaged rows" do
    active = @user.hey_emails.create!(
      external_id: "1", folder: :imbox, subject: "Keep me",
      received_at: 1.hour.ago
    )
    @user.hey_emails.create!(
      external_id: "2", folder: :imbox, subject: "Dismissed",
      received_at: 1.hour.ago, dismissed_at: Time.current
    )
    @user.hey_emails.create!(
      external_id: "3", folder: :imbox, subject: "Triaged",
      received_at: 1.hour.ago, triaged_at: Time.current
    )

    assert_equal [ active.id ], @user.hey_emails.for_triage.pluck(:id)
  end

  test "for_triage orders newest first" do
    older = @user.hey_emails.create!(
      external_id: "1", folder: :imbox, subject: "Older",
      received_at: 2.hours.ago
    )
    newer = @user.hey_emails.create!(
      external_id: "2", folder: :imbox, subject: "Newer",
      received_at: 10.minutes.ago
    )

    assert_equal [ newer.id, older.id ], @user.hey_emails.for_triage.pluck(:id)
  end

  test "dismiss! stamps dismissed_at and excludes from triage" do
    email = @user.hey_emails.create!(
      external_id: "1", folder: :imbox, subject: "Nope",
      received_at: 1.hour.ago
    )

    email.dismiss!

    assert_not_nil email.reload.dismissed_at
    assert_empty @user.hey_emails.for_triage
    assert email.handled?
  end

  test "triage! stamps triaged_at and excludes from triage" do
    email = @user.hey_emails.create!(
      external_id: "1", folder: :reply_later, subject: "Do this",
      received_at: 1.hour.ago
    )

    email.triage!

    assert_not_nil email.reload.triaged_at
    assert_empty @user.hey_emails.for_triage
    assert email.handled?
  end

  test "requires subject and received_at" do
    email = @user.hey_emails.build(external_id: "1", folder: :imbox)
    assert_not email.valid?
    assert_includes email.errors[:subject], "can't be blank"
    assert_includes email.errors[:received_at], "can't be blank"
  end
end
