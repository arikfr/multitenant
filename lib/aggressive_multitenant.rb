require 'active_record'
require 'active_support/all'

module Multitenant
  class AccessException < RuntimeError
  end

  class << self
    attr_accessor :current_tenant
    attr_accessor :in_block
    
    def initialize
      in_block = false
    end
    
    def models
      @models ||= {} 
      @models
    end

    # execute a block scoped to the current tenant
    # unsets the current tenant after execution
    def with_tenant(tenant, &block)
      Multitenant.current_tenant = tenant
      Multitenant.in_block = true
      save_and_change_default_scope_for_all
      yield
    ensure
      restore_default_scope
      Multitenant.in_block = false
      Multitenant.current_tenant = nil
    end

    def save_and_change_default_scope(model_details)
      model_details[:name].instance_eval do
        model_details[:default_scoping] = default_scoping.dup
        default_scope where(model_details[:tenant_key_name] => Multitenant.current_tenant.id)
      end
    end

    protected
      def save_and_change_default_scope_for_all
        models.values.each do |model|
          save_and_change_default_scope model
        end
      end

      def restore_default_scope
        models.values.each do |model|
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
      model_details = {:name => self, :tenant_key_name => reflection.primary_key_name}
      Multitenant.models[self.name] = model_details

      if Multitenant.in_block
        Multitenant.save_and_change_default_scope model_details
      end
      
      if prevent_changing_tenant
        # attr_readonly reflection.primary_key_name

        # I have to define the following, because attr_readonly only takes affect after reload of the object,
        # hence might introduce a security breach
        # ["#{reflection.name}", "#{reflection.primary_key_name}"].each do |name|           
        #   alias_method "original_#{name}=", "#{name}="
        #   define_method "#{name}=" do |value|
        #     puts "Will write the tenant: #{(new_record? || eval(name).nil?)}"
        #     #write_attribute(name, value) if (new_record? || eval(name).nil?)
        #     eval("original_#{name}=#{value}") if (new_record? || eval(name).nil?)
        #     # doing nothing. haha
        #   end
        # end
      end

      if enforce_on_initialize
        after_initialize do
          if Multitenant.current_tenant && self.attributes.has_key?(reflection.primary_key_name)
            tenant = eval("self.#{reflection.primary_key_name}")
            raise AccessException, "Expected: #{Multitenant.current_tenant.id}, but got: #{tenant}" unless (tenant.nil? || tenant == Multitenant.current_tenant.id)
          end
        end
      end
    end
  end
end

ActiveRecord::Base.extend Multitenant::ActiveRecordExtensions
