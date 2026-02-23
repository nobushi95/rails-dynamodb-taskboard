class Project
  include Aws::Record

  set_table_name "TaskBoard"

  string_attr :pk, hash_key: true
  string_attr :sk, range_key: true
  string_attr :project_id
  string_attr :name
  string_attr :description
  string_attr :owner_id
  string_attr :entity_type

  def self.find(owner_id, project_id)
    result = Aws::DynamoDB::Client.new.get_item(
      table_name: "TaskBoard",
      key: { "pk" => "USER##{owner_id}", "sk" => "PROJECT##{project_id}" }
    )
    return nil unless result.item
    build_from_item(result.item)
  end

  def self.find_by_project_id(project_id)
    result = Aws::DynamoDB::Client.new.scan(
      table_name: "TaskBoard",
      filter_expression: "entity_type = :type AND project_id = :pid",
      expression_attribute_values: { ":type" => "Project", ":pid" => project_id }
    )
    return nil if result.items.empty?
    build_from_item(result.items.first)
  end

  def self.for_user(user_id)
    result = Aws::DynamoDB::Client.new.query(
      table_name: "TaskBoard",
      key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
      expression_attribute_values: {
        ":pk" => "USER##{user_id}",
        ":sk_prefix" => "PROJECT#"
      }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.all_projects
    result = Aws::DynamoDB::Client.new.scan(
      table_name: "TaskBoard",
      filter_expression: "entity_type = :type",
      expression_attribute_values: { ":type" => "Project" }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.build_from_item(item)
    project = new
    project.pk = item["pk"]
    project.sk = item["sk"]
    project.project_id = item["project_id"]
    project.name = item["name"]
    project.description = item["description"]
    project.owner_id = item["owner_id"]
    project.entity_type = item["entity_type"]
    project
  end

  def save_as_project
    self.pk = "USER##{owner_id}"
    self.sk = "PROJECT##{project_id}"
    self.entity_type = "Project"
    save
  end
end
