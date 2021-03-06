module Setup
  class EmailChannel
    include CenitScoped
    include NamespaceNamed
    include ClassHierarchyAware

    abstract_class true

    build_in_data_type.referenced_by(:namespace, :name)

    def send_message(message)
      fail NotImplementedError
    end
  end
end
