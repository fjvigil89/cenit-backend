module Setup
  class Execution
    include CenitScoped
    include Setup::AttachmentUploader

    build_in_data_type.including(:task).and(
      properties: {
        time_span: {
          type: 'number'
        },
        attachment_content: {
        }
      }
    )

    deny :create, :update

    attachment_uploader

    belongs_to :task, class_name: Setup::Task.to_s, inverse_of: :executions
    has_and_belongs_to_many :notifications, class_name: Setup::SystemNotification.to_s, inverse_of: nil

    field :status, type: StringifiedSymbol, default: :pending
    field :started_at, type: DateTime
    field :completed_at, type: DateTime

    field :agent_id, type: BSON::ObjectId

    before_save { self.agent_id ||= task.agent_id }

    default_scope -> { desc(:_id) }

    def label
      task&.to_s || "#{self.class.to_s.split('::').last.to_title} ##{id}"
    end

    def start(options)
      update status: :running,
             started_at: options[:time] || Time.now
    end

    def finish(options)
      status = options[:status] || :completed
      if Setup::Task::RUNNING_STATUS.include?(status)
        status = :completed
      end
      update status: status,
             completed_at: options[:time] || Time.now
    end

    def time_span
      if (start = started_at)
        (((completed_at || Time.now).to_f) * 1000).to_i - (start.to_f * 1000).to_i
      else
        0
      end
    end

    def attachment_content
      content = nil
      if attachment.present? && (grid_file = attachment.file.grid_file).length < 1.kilobyte
        content = attachment.read
        if (metadata = grid_file.metadata) && (schema = metadata['schema']).is_a?(Hash)
          content =
            case schema['type']
            when 'integer'
              content.to_i
            when 'number'
              content.to_f
            when 'boolean'
              content.to_b
            else
              content
            end
        end
      end
      content
    end

  end
end
