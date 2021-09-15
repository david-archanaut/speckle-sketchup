require "sketchup"

class SpeckleSystems::SpeckleConnector::ConverterSketchup
  String @units

  def initialize(units = "m")
    @units = units
  end

  def self.convert_to_native
    nil
  end

  def self.can_convert_to_native(obj)
    false
  end

  def self.edge_to_native
    nil
  end

  def self.face_to_native
    nil
  end

  def self.vertex_to_native
    nil
  end

end