namespace :dynamodb do
  desc "Create TaskBoard table with GSIs"
  task create_tables: :environment do
    client = Aws::DynamoDB::Client.new

    begin
      client.create_table(
        table_name: "TaskBoard",
        key_schema: [
          { attribute_name: "pk", key_type: "HASH" },
          { attribute_name: "sk", key_type: "RANGE" }
        ],
        attribute_definitions: [
          { attribute_name: "pk", attribute_type: "S" },
          { attribute_name: "sk", attribute_type: "S" },
          { attribute_name: "gsi1pk", attribute_type: "S" },
          { attribute_name: "gsi1sk", attribute_type: "S" },
          { attribute_name: "gsi2pk", attribute_type: "S" },
          { attribute_name: "gsi2sk", attribute_type: "S" }
        ],
        global_secondary_indexes: [
          {
            index_name: "gsi1",
            key_schema: [
              { attribute_name: "gsi1pk", key_type: "HASH" },
              { attribute_name: "gsi1sk", key_type: "RANGE" }
            ],
            projection: { projection_type: "ALL" }
          },
          {
            index_name: "gsi2",
            key_schema: [
              { attribute_name: "gsi2pk", key_type: "HASH" },
              { attribute_name: "gsi2sk", key_type: "RANGE" }
            ],
            projection: { projection_type: "ALL" }
          }
        ],
        billing_mode: "PAY_PER_REQUEST"
      )
      puts "Created table: TaskBoard (with GSI1, GSI2)"
    rescue Aws::DynamoDB::Errors::ResourceInUseException
      puts "Table TaskBoard already exists, skipping."
    end
  end

  desc "Drop TaskBoard table"
  task drop_tables: :environment do
    client = Aws::DynamoDB::Client.new

    begin
      client.delete_table(table_name: "TaskBoard")
      puts "Deleted table: TaskBoard"
    rescue Aws::DynamoDB::Errors::ResourceNotFoundException
      puts "Table TaskBoard does not exist, skipping."
    end
  end

  desc "Seed sample data"
  task seed: :environment do
    client = Aws::DynamoDB::Client.new

    users = [
      { id: "user1", name: "Alice", email: "alice@example.com" },
      { id: "user2", name: "Bob", email: "bob@example.com" },
      { id: "user3", name: "Charlie", email: "charlie@example.com" }
    ]

    users.each do |u|
      client.put_item(
        table_name: "TaskBoard",
        item: {
          "pk" => "USER##{u[:id]}",
          "sk" => "METADATA",
          "user_id" => u[:id],
          "name" => u[:name],
          "email" => u[:email],
          "entity_type" => "User"
        }
      )
      puts "Created user: #{u[:name]}"
    end

    projects = [
      { id: "proj1", name: "Website Redesign", description: "Redesign the company website", owner_id: "user1" },
      { id: "proj2", name: "Mobile App", description: "Build a new mobile application", owner_id: "user1" },
      { id: "proj3", name: "API Integration", description: "Integrate third-party APIs", owner_id: "user2" },
      { id: "proj4", name: "Data Migration", description: "Migrate legacy database", owner_id: "user3" }
    ]

    projects.each do |p|
      client.put_item(
        table_name: "TaskBoard",
        item: {
          "pk" => "USER##{p[:owner_id]}",
          "sk" => "PROJECT##{p[:id]}",
          "project_id" => p[:id],
          "name" => p[:name],
          "description" => p[:description],
          "owner_id" => p[:owner_id],
          "entity_type" => "Project"
        }
      )
      puts "Created project: #{p[:name]}"
    end

    tasks = [
      { id: "task1", title: "Design mockups", project_id: "proj1", assignee_id: "user1", status: "done", due_date: "2026-03-01", priority: "high" },
      { id: "task2", title: "Implement header", project_id: "proj1", assignee_id: "user2", status: "in_progress", due_date: "2026-03-05", priority: "medium" },
      { id: "task3", title: "Write CSS styles", project_id: "proj1", assignee_id: "user1", status: "todo", due_date: "2026-03-10", priority: "medium" },
      { id: "task4", title: "Setup React Native", project_id: "proj2", assignee_id: "user2", status: "done", due_date: "2026-03-02", priority: "high" },
      { id: "task5", title: "Build login screen", project_id: "proj2", assignee_id: "user2", status: "in_progress", due_date: "2026-03-08", priority: "high" },
      { id: "task6", title: "Push notifications", project_id: "proj2", assignee_id: "user3", status: "todo", due_date: "2026-03-15", priority: "low" },
      { id: "task7", title: "Research APIs", project_id: "proj3", assignee_id: "user2", status: "done", due_date: "2026-02-28", priority: "medium" },
      { id: "task8", title: "OAuth integration", project_id: "proj3", assignee_id: "user3", status: "in_progress", due_date: "2026-03-06", priority: "high" },
      { id: "task9", title: "Write API tests", project_id: "proj3", assignee_id: "user2", status: "todo", due_date: "2026-03-12", priority: "medium" },
      { id: "task10", title: "Schema mapping", project_id: "proj4", assignee_id: "user3", status: "done", due_date: "2026-03-01", priority: "high" },
      { id: "task11", title: "Write migration scripts", project_id: "proj4", assignee_id: "user3", status: "in_progress", due_date: "2026-03-07", priority: "high" },
      { id: "task12", title: "Validate data", project_id: "proj4", assignee_id: "user1", status: "todo", due_date: "2026-03-14", priority: "medium" }
    ]

    tasks.each do |t|
      client.put_item(
        table_name: "TaskBoard",
        item: {
          "pk" => "PROJECT##{t[:project_id]}",
          "sk" => "TASK##{t[:due_date]}##{t[:id]}",
          "task_id" => t[:id],
          "title" => t[:title],
          "project_id" => t[:project_id],
          "assignee_id" => t[:assignee_id],
          "status" => t[:status],
          "due_date" => t[:due_date],
          "priority" => t[:priority],
          "entity_type" => "Task",
          "gsi1pk" => "STATUS##{t[:status]}",
          "gsi1sk" => "#{t[:due_date]}##{t[:id]}",
          "gsi2pk" => "ASSIGNEE##{t[:assignee_id]}",
          "gsi2sk" => "#{t[:due_date]}##{t[:id]}"
        }
      )
      puts "Created task: #{t[:title]}"
    end

    puts "\nSeed complete! Created #{users.size} users, #{projects.size} projects, #{tasks.size} tasks."
  end
end
