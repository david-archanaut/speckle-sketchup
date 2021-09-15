require "sketchup"

module SpeckleSystems::SpeckleConnector
  class ConverterSketchup
    SKETCHUP_UNIT_STRINGS = { "m" => "m", "mm" => "mm", "ft" => "feet", "in" => "inch", "yd" => "yard" }.freeze
    public_constant :SKETCHUP_UNIT_STRINGS

    attr_accessor :units, :component_defs

    def initialize(units = "m")
      @units = units
      @component_defs = {}
    end

    def convert_to_speckle(obj)
      case obj.typename
      when "Edge" then edge_to_speckle(obj)
      when "Face" then face_to_speckle(obj)
      when "Group" then component_instance_to_speckle(obj, is_group: true)
      when "ComponentDefinition" then component_definition_to_speckle(obj)
      when "ComponentInstance" then component_instance_to_speckle(obj)
      else
        nil
      end
    end

    def can_convert_to_speckle(_typename)
      false
    end

    def length_to_speckle(length)
      length.__send__("to_#{SKETCHUP_UNIT_STRINGS[@units]}")
    end

    def edge_to_speckle(edge)
      {
        speckle_type: "Objects.Geometry.Line",
        applicationId: edge.persistent_id.to_s,
        units: @units,
        start: vertex_to_speckle(edge.start),
        end: vertex_to_speckle(edge.end),
        domain: speckle_interval(0, Float(edge.length)),
        bbox: bounds_to_speckle(edge.bounds)
      }
    end

    def component_definition_to_speckle(definition)
      {
        speckle_type: "Objects.Other.BlockDefinition",
        applicationId: definition.guid,
        units: @units,
        name: definition.name,
        # i think the base point is always the origin?
        basePoint: speckle_point,
        geometry: definition.entities.filter_map { |entity| convert_to_speckle(entity) if entity.typename != "Edge" }
      }
    end

    def component_instance_to_speckle(instance, is_group: false)
      transform = instance.transformation
      origin = transform.origin
      {
        speckle_type: "Objects.Other.BlockInstance",
        applicationId: instance.guid,
        is_sketchup_group: is_group,
        units: @units,
        name: instance.name,
        renderMaterial: instance.material.nil? ? nil : material_to_speckle(instance.material),
        transform: transform_to_speckle(transform),
        insertionPoint: speckle_point(origin[0], origin[1], origin[2]),
        blockDefinition: component_definition_to_speckle(instance.definition)
      }
    end

    def transform_to_speckle(transform)
      t_arr = transform.to_a
      [
        t_arr[0],
        t_arr[4],
        t_arr[8],
        length_to_speckle(t_arr[12]),
        t_arr[1],
        t_arr[5],
        t_arr[9],
        length_to_speckle(t_arr[13]),
        t_arr[2],
        t_arr[6],
        t_arr[10],
        length_to_speckle(t_arr[14]),
        t_arr[3],
        t_arr[7],
        t_arr[11],
        t_arr[12]
      ]
    end

    def mesh_to_speckle(component_def)
      vertices = []
      faces = []
      pt_count = 0
      component_def.entities.each do |entity|
        next unless entity.typename == "Face"

        mesh = entity.mesh
        mesh.points.each do |pt|
          vertices.push(length_to_speckle(pt[0]), length_to_speckle(pt[1]), length_to_speckle(pt[2]))
        end
        mesh.polygons.each do |poly|
          faces.push(
            case poly.count
            when 3 then 0   # tris
            when 4 then 1   # polys
            else
              poly.count    # ngons
            end
          )
          faces.push(*poly.map { |coord| coord.abs + pt_count })
        end
        pt_count += mesh.points.count
      end

      {
        speckle_type: "Objects.Geometry.Mesh",
        units: @units,
        vertices: vertices,
        faces: faces
      }
    end

    def face_to_speckle(face)
      vertices = []
      faces = []
      mesh = face.mesh
      mesh.points.each do |pt|
        vertices.push(length_to_speckle(pt[0]), length_to_speckle(pt[1]), length_to_speckle(pt[2]))
      end
      mesh.polygons.each do |poly|
        faces.push(
          case poly.count
          when 3 then 0   # tris
          when 4 then 1   # polys
          else
            poly.count    # ngons
          end
        )
        faces.push(*poly.map { |coord| coord.abs - 1 })
      end

      {
        speckle_type: "Objects.Geometry.Mesh",
        units: @units,
        renderMaterial: face.material.nil? ? nil : material_to_speckle(face.material),
        bbox: bounds_to_speckle(face.bounds),
        vertices: vertices,
        faces: faces
      }
    end

    def vertex_to_speckle(vertex)
      point = vertex.position
      {
        speckle_type: "Objects.Geometry.Point",
        units: @units,
        x: length_to_speckle(point[0]),
        y: length_to_speckle(point[1]),
        z: length_to_speckle(point[2])
      }
    end

    def material_to_speckle(material)
      rgba = material.color.to_a
      {
        speckle_type: "Objects.Other.RenderMaterial",
        name: material.name,
        diffuse: [rgba[3] << 24 | rgba[0] << 16 | rgba[1] << 8 | rgba[2]].pack("l").unpack1("l"),
        opacity: material.alpha,
        emissive: -16_777_216,
        metalness: 0,
        roughness: 1
      }
    end

    def bounds_to_speckle(bounds)
      min_pt = bounds.min
      {
        speckle_type: "Objects.Geometry.Box",
        units: @units,
        area: 0,
        volume: 0,
        xSize: speckle_interval(min_pt[0], bounds.width),
        ySize: speckle_interval(min_pt[1], bounds.height),
        zSize: speckle_interval(min_pt[2], bounds.depth),
        basePlane: speckle_plane
      }
    end

    def speckle_interval(start_val, end_val)
      {
        speckle_type: "Objects.Primitive.Interval",
        units: @units,
        start: start_val.is_a?(Length) ? length_to_speckle(start_val) : start_val,
        end: end_val.is_a?(Length) ? length_to_speckle(end_val) : end_val
      }
    end

    def speckle_point(x = 0.0, y = 0.0, z = 0.0, vector: false)
      {
        speckle_type: vector ? "Objects.Geometry.Vector" : "Objects.Geometry.Point",
        units: @units,
        x: x.is_a?(Length) ? length_to_speckle(x) : x,
        y: y.is_a?(Length) ? length_to_speckle(y) : y,
        z: z.is_a?(Length) ? length_to_speckle(z) : z
      }
    end

    def speckle_vector(x = 0.0, y = 0.0, z = 0.0)
      speckle_point(x, y, z, vector: true)
    end

    def speckle_plane(xdir: [1, 0, 0], ydir: [0, 1, 0], normal: [0, 0, 1], origin: [0, 0, 0])
      {
        speckle_type: "Objects.Geometry.Plane",
        units: @units,
        xdir: speckle_vector(*xdir),
        ydir: speckle_vector(*ydir),
        normal: speckle_vector(*normal),
        origin: speckle_point(*origin)
      }
    end
  end
end
