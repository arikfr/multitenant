require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

ActiveRecord::Schema.define(:version => 1) do
  create_table :companies, :force => true do |t|
    t.column :name, :string
  end

  create_table :users, :force => true do |t|
    t.column :name, :string
    t.column :dummy, :integer, :default => 1
    t.column :company_id, :integer
  end


  create_table :tenants, :force => true do |t|
    t.column :name, :string
  end

  create_table :items, :force => true do |t|
    t.column :name, :string
    t.column :tenant_id, :integer
  end
end

class Company < ActiveRecord::Base
  has_many :users
end
class User < ActiveRecord::Base
  belongs_to :company
  belongs_to_multitenant :company
  default_scope where(:dummy => 1)
end

class Tenant < ActiveRecord::Base
  has_many :items
end
class Item < ActiveRecord::Base
  belongs_to :tenant
  belongs_to_multitenant
end

describe Multitenant do
  before { @foo = Company.create!(:name => 'foo') }
  after { Multitenant.current_tenant = nil }

  describe 'Multitenant.current_tenant' do
    before { Multitenant.current_tenant = :foo }
    it { Multitenant.current_tenant == :foo }
  end

  describe 'Multitenant.with_tenant block' do
    before do
      @executed = false
      Multitenant.with_tenant @foo do
        Multitenant.current_tenant.should == @foo
        @executed = true
      end
    end

    it 'clears current_tenant after block runs' do
      Multitenant.current_tenant.should == nil
    end

    it 'yields the block' do
      @executed.should == true
    end    
  end

  describe 'Multitenant.with_tenant block that raises error' do
    before do
      @executed = false
      lambda {
        Multitenant.with_tenant @foo do
          @executed = true
          raise 'expected error'
        end
      }.should raise_error('expected error')
    end

    it 'clears current_tenant after block runs' do
      Multitenant.current_tenant.should == nil
    end

    it 'yields the block' do
      @executed.should == true
    end    
  end

  describe 'User.all when current_tenant is set' do
    before do
      User.destroy_all
      @company = Company.create!(:name => 'foo')
      @company2 = Company.create!(:name => 'bar')

      @user = @company.users.create! :name => 'bob'
      @user2 = @company2.users.create! :name => 'tim'

      Multitenant.with_tenant @company do
        @users = User.all
      end
    end
    it { @users.length.should == 1 }
    it { @users.should == [@user] }
    
    it "should allow switching tenant" do
      Multitenant.with_tenant @company2 do
        @users = User.all
      end
      @users.length.should == 1
      @users.should == [@user2]
    end
    
    describe "should preserve already set default_scope" do
      before do
        @user3 = @company.users.create! :name => 'hide me', :dummy => 2
      end
      
      it "will use it while in tenant" do
        Multitenant.with_tenant @company do
          @users = User.all
        end
        @users.should == [@user]
      end
      
      it "will restore it after mutlitenant block" do
        Multitenant.with_tenant @company do
        end
        User.all.should == [@user, @user2]
      end

      it "should allow to break from scope" do
        pending "Don't know hot to implement"
        Multitenant.with_tenant @company do
          User.unscoped.should == [@user, @user2]
        end        
      end
    end
  end

  describe "When in tenant scope should create objects correctly" do
    before do
      @company = Company.create! :name => "bar"
      @company2 = Company.create! :name => "foo"

      Multitenant.with_tenant @company do
        @user = User.create! :name => "bar user"
      end
    end

    it "should set the tenant on new objects" do
      @user.company_id.should == @company.id
    end

    it "should prevent changing the tenant id through assigment to id" do
      @user.company_id = @company2.id
      @user.company.should == @company
      @user.save.should be_true
      @user.company_id.should == @company.id
      @user.reload
      @user.company_id.should == @company.id
    end

    it "should prevent changing the tenant id through direct assigment" do
      @user.company = @company2
      @user.company.should == @company
      @user.save.should be_true
      @user.company_id.should == @company.id
      @user.reload
      @user.company_id.should == @company.id
    end
  end

  describe "When current tenant is set" do
    before do
      @company = Company.create! :name => "for"
      @company2 = Company.create! :name => "bar"
      @user = @company.users.create! :name => "foo user"
      @user2 = @company2.users.create! :name => "bar user"

      Multitenant.current_tenant = @company
    end

    it "should throw exception in case of getting objects from different tenant" do
      lambda { @user_reload = User.find @user2.id }.should raise_error(Multitenant::AccessException)
    end

    it "should prevent creating objects for other tenant" do
      lambda { @company2.users.create! :name => "other" }.should raise_error(Multitenant::AccessException)
    end

    it "should prevent updating to wrong tenant"
  end

  describe 'Item.all when current_tenant is set' do
    before do
      @tenant = Tenant.create!(:name => 'foo')
      @tenant2 = Tenant.create!(:name => 'bar')

      @item = @tenant.items.create! :name => 'baz'
      @item2 = @tenant2.items.create! :name => 'booz'
      Multitenant.with_tenant @tenant do
        @items = Item.all
      end
    end
    it { @items.length.should == 1 }
    it { @items.should == [@item] }
  end


  describe 'When creating new object and current_tenant is set' do
    before do
      @company = Company.create! :name => 'foo'
      Multitenant.with_tenant @company do
        @user = User.create! :name => 'jimmy'
      end
    end
    
    it 'should set the tenant for new objects' do
      @user.company_id.should == @company.id
    end
  end

end
