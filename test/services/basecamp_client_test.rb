require "test_helper"

class BasecampClientTest < ActiveSupport::TestCase
  test "normalize_my_assignments_payload flattens priorities and non_priorities" do
    user = users(:one)
    client = BasecampClient.new(user)

    payload = {
      "priorities" => [
        {
          "id" => 101,
          "type" => "todo",
          "content" => "Priority",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "Project A" }
        }
      ],
      "non_priorities" => [
        {
          "id" => 102,
          "type" => "todo",
          "content" => "Later",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "Project A" }
        }
      ]
    }

    list = client.send(:normalize_my_assignments_payload, payload)
    assert_equal 2, list.size
    assert_equal [ 101, 102 ], list.map { |a| a["id"] }
  end

  test "normalize_my_assignments_payload includes nested todo children" do
    user = users(:one)
    client = BasecampClient.new(user)

    payload = {
      "priorities" => [],
      "non_priorities" => [
        {
          "id" => 200,
          "type" => "todo",
          "content" => "Parent",
          "completed" => false,
          "bucket" => { "id" => 1, "name" => "P" },
          "children" => [
            {
              "id" => 201,
              "type" => "todo",
              "content" => "Child step",
              "completed" => false,
              "bucket" => { "id" => 1, "name" => "P" }
            }
          ]
        }
      ]
    }

    list = client.send(:normalize_my_assignments_payload, payload)
    assert_equal 2, list.size
    assert_includes list.map { |a| a["id"] }, 201
  end
end
