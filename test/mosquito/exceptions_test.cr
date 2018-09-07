require "../test_helper"

describe "Mosquito exceptions" do
  it "declares JobFailed" do
    Mosquito::JobFailed.new "test"
  end

  it "declares DoubleRun" do
    Mosquito::DoubleRun.new "test"
  end

  it "declares IrretrievableParameter" do
    Mosquito::IrretrievableParameter.new "test"
  end
end
