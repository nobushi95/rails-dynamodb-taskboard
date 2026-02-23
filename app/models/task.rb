class Task
  include Aws::Record

  set_table_name "TaskBoard"

  string_attr :pk, hash_key: true
  string_attr :sk, range_key: true
  string_attr :task_id
  string_attr :title
  string_attr :project_id
  string_attr :assignee_id
  string_attr :status
  string_attr :due_date
  string_attr :priority
  string_attr :entity_type
  string_attr :gsi1pk
  string_attr :gsi1sk
  string_attr :gsi2pk
  string_attr :gsi2sk

  STATUSES = %w[todo in_progress done].freeze
  PRIORITIES = %w[low medium high].freeze

  def self.for_project(project_id)
    result = Aws::DynamoDB::Client.new.query(
      table_name: "TaskBoard",
      key_condition_expression: "pk = :pk AND begins_with(sk, :sk_prefix)",
      expression_attribute_values: {
        ":pk" => "PROJECT##{project_id}",
        ":sk_prefix" => "TASK#"
      }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.for_project_due_before(project_id, date)
    result = Aws::DynamoDB::Client.new.query(
      table_name: "TaskBoard",
      key_condition_expression: "pk = :pk AND sk BETWEEN :sk_start AND :sk_end",
      expression_attribute_values: {
        ":pk" => "PROJECT##{project_id}",
        ":sk_start" => "TASK#",
        ":sk_end" => "TASK##{date}~"
      }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.by_status(status)
    result = Aws::DynamoDB::Client.new.query(
      table_name: "TaskBoard",
      index_name: "gsi1",
      key_condition_expression: "gsi1pk = :pk",
      expression_attribute_values: {
        ":pk" => "STATUS##{status}"
      }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.by_assignee(user_id)
    result = Aws::DynamoDB::Client.new.query(
      table_name: "TaskBoard",
      index_name: "gsi2",
      key_condition_expression: "gsi2pk = :pk",
      expression_attribute_values: {
        ":pk" => "ASSIGNEE##{user_id}"
      }
    )
    result.items.map { |item| build_from_item(item) }
  end

  def self.find_by_task_id(project_id, task_id)
    tasks = for_project(project_id)
    tasks.find { |t| t.task_id == task_id }
  end

  def self.build_from_item(item)
    task = new
    task.pk = item["pk"]
    task.sk = item["sk"]
    task.task_id = item["task_id"]
    task.title = item["title"]
    task.project_id = item["project_id"]
    task.assignee_id = item["assignee_id"]
    task.status = item["status"]
    task.due_date = item["due_date"]
    task.priority = item["priority"]
    task.entity_type = item["entity_type"]
    task.gsi1pk = item["gsi1pk"]
    task.gsi1sk = item["gsi1sk"]
    task.gsi2pk = item["gsi2pk"]
    task.gsi2sk = item["gsi2sk"]
    task
  end

  def save_as_task
    self.pk = "PROJECT##{project_id}"
    self.sk = "TASK##{due_date}##{task_id}"
    self.entity_type = "Task"
    self.gsi1pk = "STATUS##{status}"
    self.gsi1sk = "#{due_date}##{task_id}"
    self.gsi2pk = "ASSIGNEE##{assignee_id}"
    self.gsi2sk = "#{due_date}##{task_id}"
    save
  end

  def next_status
    current_index = STATUSES.index(status) || 0
    STATUSES[(current_index + 1) % STATUSES.size]
  end

  def status_label
    case status
    when "todo" then "Todo"
    when "in_progress" then "In Progress"
    when "done" then "Done"
    else status
    end
  end

  def priority_label
    priority&.capitalize || "Medium"
  end
end
