module Mosquito
  # When a job fails
  class JobFailed < Exception
  end

  # When a task tries to run twice
  class DoubleRun < Exception
  end

  # When a job contains a model_id parameter pointing to a database record but the database doesn't return anything for that id.
  class IrretrievableParameter < Exception
  end
end
