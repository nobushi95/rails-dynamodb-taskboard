class User
  include Aws::Record

  set_table_name "TaskBoard"

  string_attr :pk, hash_key: true
  string_attr :sk, range_key: true
  string_attr :user_id
  string_attr :name
  string_attr :email
  string_attr :entity_type

  def self.find(user_id)
    result = Aws::DynamoDB::Client.new.get_item(
      table_name: "TaskBoard",
      key: { "pk" => "USER##{user_id}", "sk" => "METADATA" }
    )
    return nil unless result.item
    build_from_item(result.item)
  end

  def self.all_users
    result = Aws::DynamoDB::Client.new.scan(
      table_name: "TaskBoard",
      filter_expression: "entity_type = :type",
      expression_attribute_values: { ":type" => "User" }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.build_from_item(item)
    user = new
    user.pk = item["pk"]
    user.sk = item["sk"]
    user.user_id = item["user_id"]
    user.name = item["name"]
    user.email = item["email"]
    user.entity_type = item["entity_type"]
    user
  end

  def save_as_user
    self.pk = "USER##{user_id}"
    self.sk = "METADATA"
    self.entity_type = "User"
    save
  end
end
