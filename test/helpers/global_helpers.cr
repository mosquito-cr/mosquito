# Testing wedge which provides a clean slate to ensure tests
# aren't dependent on each other.
def clean_slate(&block)
  Mosquito::Base.bare_mapping do
    backend = Mosquito.backend
    backend.flush
    yield
  end
end
