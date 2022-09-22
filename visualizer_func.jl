import Pkg
import GeometricTools as gt
include("airfoil_func.jl")


function construct_wing(origin, file_name, b, sweep, dihedral, y_pos, chords, airfoil_files::Vector{<:AbstractString}; prompt=true,
        n_upper = 20,             # Number of sections in upper surface of blade
        n_lower = 20,             # Number of sections in lower surface of blade
        n_airfoils = 30,          # total number of airfoil sections
        plot_airfoils = false,
        symmetric = true,
        run_paraview = true
        )
    println("Constructing $file_name...")
    y_pos *= b
    for i in 1:2^symmetric
        prev_time = time()
        r = [8.0 for _ in 1:length(airfoil_files)]           # Expansion ratio in both surfaces of each airfoil
        if i == 2
            y_pos .*= -1
        end

        # GEOMETRY DEFINITION
        sign_tool = i==1 ? 1 : -1
        x_pos = [sign_tool*y*tan(sweep[i]) for (i,y) in enumerate(y_pos)]
        z_pos = [sign_tool*y*tan(dihedral[i]) for (i,y) in enumerate(y_pos)]

        # PARAMETERS
        dys = [y_pos[i+1]-y_pos[i] for i in 1:length(y_pos)-1] ./ (y_pos[end] - y_pos[1]) # normalized dy of each section
        sections = [[(1.0, Int(ceil(dy * n_airfoils)), 1.0, false)] for dy in dys]      # Discretization between each airfoil

        # Leading edge position of each airfoil
        Os = [ [x_pos[i], y_pos[i], z_pos[i]] for i in 1:size(airfoil_files)[1]]
        # Orientation of chord of each airfoil (yaw, pitch, roll)
        orien = [ [0.0, 0.0, 270.0] for _ in 1:length(y_pos)]

        crosssections = []        # It will store here the cross sections for lofting
        point_datas = []          # Dummy point data for good looking visuals

        prev_time = time()

        # Processes each airfoil geometry
        styles = ["--k", "--r", "--g", "--b", "--y", "--c"]
        org_points = []
        for (i,airfoil_file) in enumerate(airfoil_files)
            if startswith(airfoil_file, "naca") && !endswith(airfoil_file, ".dat")
                airfoil_file = [airfoil_file[5:end], 50]
            else
                airfoil_file = (joinpath("airfoils",airfoil_file),)
            end

            # Read airfoil file
            x,y = airfoil_xy(airfoil_file...)
            push!(org_points, [x,y])

            # Separate upper and lower sides to make the contour injective in x
            i_le = findfirst(r -> (r)==minimum(x), x)
            upper = [reverse(x[1:i_le]), reverse(y[1:i_le])]
            lower = [x[i_le:end], y[i_le:end]]

            # Parameterize both sides independently
            fun_upper = gt.parameterize(upper[1], upper[2], zeros(eltype(upper[1]), size(upper[1])); inj_var=1)
            fun_lower = gt.parameterize(lower[1], lower[2], zeros(eltype(lower[1]), size(lower[1])); inj_var=1)

            # New discretization for both surfaces
            upper_points = gt.discretize(fun_upper, 0, 1, n_upper, r[i]; central=true)
            lower_points = gt.discretize(fun_lower, 0, 1, n_lower, r[i]; central=true)

            # Put both surfaces back together from TE over the top and from LE over the bottom.
            reverse!(upper_points)                           # Trailing edge over the top
            new_x = [point[1] for point in upper_points]
            new_y = [point[2] for point in upper_points]      # Leading edge over the bottom
            new_x = vcat(new_x, [point[1] for point in lower_points])
            new_y = vcat(new_y, [point[2] for point in lower_points])

            gt.plot_airfoil(new_x, new_y; style=styles[i], label=airfoil_file)

            # Scales the airfoil acording to its chord length
            new_x = chords[i]*new_x
            new_y = chords[i]*new_y

            # Reformats into points
            npoints = size(new_x)[1]
            airfoil = Array{Float64, 1}[[new_x[j], new_y[j], 0] for j in 1:npoints]

            # Positions the airfoil along the blade in the right orientation
            Oaxis = gt.rotation_matrix(orien[i][1], orien[i][2], orien[i][3])
            invOaxis = inv(Oaxis)
            airfoil = gt.countertransform(airfoil, invOaxis, Os[i])

            push!(crosssections, airfoil)
            push!(point_datas, [j for j in npoints*(i-1) .+ 1:npoints*i])
        end

        # Generates cells in VTK Legacy format
        out = gt.multilines2vtkmulticells(crosssections, sections;
                                            point_datas=point_datas)
        points, vtk_cells, point_data = out
        points = gt.transform.(points, Ref([1.0 0 0; 0 1.0 0; 0 0 1]), Ref(-origin))


        # Formats the point data for generateVTK
        data = []
        push!(data, Dict(
                    "field_name" => "Point_index",
                    "field_type" => "scalar",
                    "field_data" => point_data
                    )
        )

        # Generates the vtk file
        tag = i == 1 ? "_right" : "_left"
        gt.generateVTK(file_name*tag, points; cells=vtk_cells, point_data=data)
    end
    # Calls paraview
    vtk_files = String[]
    for i in 1:2^symmetric
        tag = i == 1 ? "_right.vtk;" : "_left.vtk;"
        push!(vtk_files, file_name*tag)
    end
    println("Done.")
    return vtk_files
end

function launch_paraview(vtk_files)
    run(`paraview --data="$(prod(vtk_files))"`)
end
