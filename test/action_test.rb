require_relative 'test_helper'

describe Action do
  before do
    @action = Action.new
  end
  describe "testing specs" do
    it "must be an instance of Action" do
      @action.instance_of? Action
    end
  end
end
