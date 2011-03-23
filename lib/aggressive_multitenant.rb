require 'active_record'
require 'active_support/all'

module Multitenant
  class AccessException < RuntimeError
  end

  class << self
    attr_accessor :current_tenant
    
    def models
      @models ||= []
      @models
    end

    # execute a block scoped to the current tenant
    # unsets the current tenant after execution
    def with_tenant(tenant, &block)
      Multitenant.current_tenant = tenant
      save_and_change_default_scope  
      yield
    ensure
      restore_default_scope
      Multitenant.current_tenant = nil
    end

    protected
      def save_and_change_default_scope
        @models.each do |model|
          model[:name].instance_eval do
            model[:default_scoping] = default_scoping.dup
            default_scope where(model[:tenant_key_name] => Multitenant.current_tenant.id)
          end
        end
      end

      def restore_default_scope
        @models.each do |model|
          # we can't use instance_eval here, because instance_eval adds another class to 
          # the hierchy, while :default_scoping doesn't change in inherited classes
          # because it is defined with class_inheritable_accessor 
          model[:name].send :reset_scoped_methods
          model[:name].send :default_scoping=, model[:default_scoping].dup
        end  
      end

  end

  module ActiveRecordExtensions
    # register the current model with the Multitenant model
    def belongs_to_multitenant(association = :tenant, enforce_on_initialize = true, prevent_changing_tenant = true)
      reflection = reflect_on_association association
      Multitenant.models << {:name => self, :tenant_key_name => reflection.primary_key_name}

      if prevent_changing_tenant
        attr_readonly reflection.primary_key_name

        # I have to define the following, because attr_readonly only takes affect after reload of the object,
        # hence might introduce a security breach
        ["#{reflection.name}=", "#{reflection.primary_key_name}="].each do |name| 
          define_method name do |value|
            super value if new_record?
            # doing nothing. haha
          end
        end
      end

      if enforce_on_initialize
        after_initialize do
          if Multitenant.current_tenant
            raise AccessException unless eval("self.#{reflection.primary_key_name}") == Multitenant.current_tenant.id
          end
        end
      end
    end
  end
end

ActiveRecord::Base.extend Multitenant::ActiveRecordExtensions