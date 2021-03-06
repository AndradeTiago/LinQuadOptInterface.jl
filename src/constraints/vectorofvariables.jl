#=
    Vector valued bounds
        VectorOfVariables -in- Nonnegatives
        VectorOfVariables -in- Nonpositives
        VectorOfVariables -in- Zeros

    SOS
        VectorOfVariables -in- SOS1
        VectorOfVariables -in- SOS2
=#
constrdict(m::LinQuadOptimizer, ::VVCI{MOI.Nonnegatives}) = cmap(m).vv_nonnegatives
constrdict(m::LinQuadOptimizer, ::VVCI{MOI.Nonpositives}) = cmap(m).vv_nonpositives
constrdict(m::LinQuadOptimizer, ::VVCI{MOI.Zeros}) = cmap(m).vv_zeros

constrdict(m::LinQuadOptimizer, ::VVCI{SOS1}) = cmap(m).sos1
constrdict(m::LinQuadOptimizer, ::VVCI{SOS2}) = cmap(m).sos2

function MOI.addconstraint!(m::LinQuadOptimizer, func::VecVar, set::S) where S <: VecLinSets
    @assert length(func.variables) == MOI.dimension(set)
    m.last_constraint_reference += 1
    ref = VVCI{S}(m.last_constraint_reference)
    rows = get_number_linear_constraints(m)
    n = MOI.dimension(set)
    add_linear_constraints!(m,
        CSRMatrix{Float64}(collect(1:n), getcol.(m, func.variables), ones(n)),
        fill(backend_type(m, set),n),
        zeros(n)
    )
    dict = constrdict(m, ref)
    dict[ref] = collect(rows+1:rows+n)
    append!(m.constraint_primal_solution, fill(NaN,n))
    append!(m.constraint_dual_solution, fill(NaN,n))
    append!(m.constraint_constant, fill(0.0,n))
    return ref
end

MOI.candelete(m::LinQuadOptimizer, c::VVCI{S}) where S <: VecLinSets = MOI.isvalid(m, c)
function MOI.delete!(m::LinQuadOptimizer, c::VVCI{S}) where S <: VecLinSets
    deleteconstraintname!(m, c)
    dict = constrdict(m, c)
    # we delete rows from largest to smallest here so that we don't have
    # to worry about updating references in a greater numbered row, only to
    # modify it later.
    for row in sort(dict[c], rev=true)
        delete_linear_constraints!(m, row, row)
        deleteat!(m.constraint_primal_solution, row)
        deleteat!(m.constraint_dual_solution, row)
        deleteat!(m.constraint_constant, row)
        # shift all the other references
        shift_references_after_delete_affine!(m, row)
    end
    delete!(dict, c)
end

#=
    Get constraint set of vector variable bound
=#

MOI.canget(m::LinQuadOptimizer, ::MOI.ConstraintSet, ::Type{VVCI{S}}) where S <: VecLinSets = true
function MOI.get(m::LinQuadOptimizer, ::MOI.ConstraintSet, c::VVCI{S}) where S <: VecLinSets
    S(length(m[c]))
end

#=
    Get constraint function of vector variable bound (linear ctr)
=#

MOI.canget(m::LinQuadOptimizer, ::MOI.ConstraintFunction, ::Type{VVCI{S}}) where S <: VecLinSets = true
function MOI.get(m::LinQuadOptimizer, ::MOI.ConstraintFunction, c::VVCI{<: VecLinSets})
    refs = m[c]
    out = VarInd[]
    sizehint!(out, length(refs))
    for ref in refs
        colidx, coefs = get_linear_constraint(m, ref)
        if length(colidx) != 1
            error("Unexpected constraint")
        end
        push!(out,m.variable_references[colidx[1]])
    end
    return VecVar(out)
end

#=
    SOS constraints
=#

function MOI.addconstraint!(m::LinQuadOptimizer, v::VecVar, sos::S) where S <: Union{MOI.SOS1, MOI.SOS2}
    make_problem_type_integer(m)
    add_sos_constraint!(m, getcol.(m, v.variables), sos.weights, backend_type(m, sos))
    m.last_constraint_reference += 1
    ref = VVCI{S}(m.last_constraint_reference)
    dict = constrdict(m, ref)
    dict[ref] = length(cmap(m).sos1) + length(cmap(m).sos2) + 1
    ref
end

MOI.candelete(m::LinQuadOptimizer, c::VVCI{<:Union{SOS1, SOS2}}) = MOI.isvalid(m, c)
function MOI.delete!(m::LinQuadOptimizer, c::VVCI{<:Union{SOS1, SOS2}})
    deleteconstraintname!(m, c)
    dict = constrdict(m, c)
    idx = dict[c]
    delete_sos!(m, idx, idx)
    deleteref!(cmap(m).sos1, idx, c)
    deleteref!(cmap(m).sos2, idx, c)
    if !hasinteger(m)
        make_problem_type_continuous(m)
    end
end

MOI.canget(m::LinQuadOptimizer, ::MOI.ConstraintSet, ::Type{VVCI{S}}) where S <: Union{MOI.SOS1, MOI.SOS2} = true
function MOI.get(m::LinQuadOptimizer, ::MOI.ConstraintSet, c::VVCI{S}) where S <: Union{MOI.SOS1, MOI.SOS2}
    indices, weights, types = get_sos_constraint(m, m[c])
    set = S(weights)
    @assert types == backend_type(m, set)
    return set
end

MOI.canget(m::LinQuadOptimizer, ::MOI.ConstraintFunction, ::Type{VVCI{S}}) where S <: Union{MOI.SOS1, MOI.SOS2} = true
function MOI.get(m::LinQuadOptimizer, ::MOI.ConstraintFunction, c::VVCI{<:Union{SOS1, SOS2}})
    indices, weights, types = get_sos_constraint(m, m[c])
    return VecVar(m.variable_references[indices])
end
