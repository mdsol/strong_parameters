#marker module to identify boolean objects.

module Boolean
end

class TrueClass
  include Boolean
end

class FalseClass
  include Boolean
end
