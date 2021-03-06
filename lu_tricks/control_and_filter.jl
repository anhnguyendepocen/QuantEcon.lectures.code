#=
Classical discrete time LQ optimal control and filtering problems. The
control problems we consider take the form

    \max \sum_{t = 0}^N \beta^t \{a_t y_t - h y^2_t / 2 - [d(L)y_t]^2 \}

subject to h > 0, 0 < \beta < 1 and

 * y_{-1},y_{-2}, \dots, y_{-m} (initial conditions)

 * d(L) = d_0 + d_1L + d_2L^2 + \dots + d_mL^m

The sequence {y_t} is scalar

Authors: Shunsuke Hori
=#

using Polynomials

type LQFilter
    d::Array
    h::Real
    y_m::Array
    m::Integer
    phi::Vector
    beta::Real
    phi_r::Union{Vector,Void}
    k::Union{Integer,Void}
end


"""
Parameters
----------
d : Array (1-D or a 2-D column vector)
        The order of the coefficients: [d_0, d_1, ..., d_m]
h : Real
        Parameter of the objective function (corresponding to the
        quadratic term)
y_m : Array (1-D or a 2-D column vector)
        Initial conditions for y
r : Array (1-D or a 2-D column vector)
        The order of the coefficients: [r_0, r_1, ..., r_k]
        (optional, if not defined -> deterministic problem)
beta : Real or nothing
        Discount factor (optional, default value is one)
h_eps : 
"""
function LQFilter{TD<:Real}(d::Array{TD},
                   h::Real,
                   y_m::Array;
                   r::Union{Array,Void}=nothing,
                   beta::Union{Real,Void}=nothing,
                   h_eps::Union{Real,Void}=nothing,
                   )

    if ndims(d) > 2 || ndims(y_m) > 2
        throw(ArgumentError("d and y_m must be vector or 2-D array"))
    end

    if size(d,2) != 1 || size(y_m,2) != 1
        throw(ArgumentError("d and y_m must be columnvector"))
    end
    d = d''
    y_m = y_m''

    m = size(d,1) - 1

    m == size(y_m,1) ||
        throw(ArgumentError("y_m and d must be of same length = $m"))

    #---------------------------------------------
    # Define the coefficients of phi up front
    #---------------------------------------------

    phi = Vector{TD}(2m + 1)
    for i in -m:m
        phi[m-i+1] = sum(diag(d*d', -i))
    end
    phi[m+1] = phi[m+1] + h

    #-----------------------------------------------------
    # If r is given calculate the vector phi_r
    #-----------------------------------------------------
    
    if r == nothing
        k=nothing
        phi_r = nothing
    else
        TR=eltype(r)
        k = size(r,1) - 1
        phi_r = Array{TR}(2k + 1)

        for i = -k:k
            phi_r[k-i+1] = sum(diag(r*r', -i))
        end

        if h_eps != nothing
            phi_r[k+1] = phi_r[k+1] + h_eps
        end
    end

    #-----------------------------------------------------
    # If beta is given, define the transformed variables
    #-----------------------------------------------------
    if beta == nothing
        beta = 1.0
    else
        d = beta.^(collect(0:m)/2) * d
        y_m = y_m * beta.^(- collect(1:m)''/2)
    end

    return LQFilter(d,h,y_m,m,phi,beta,phi_r,k)
end

"""
This constructs the matrices W and W_m for a given number of periods N
"""
function construct_W_and_Wm(lqf::LQFilter, N)

    d, m = lqf.d, lqf.m

    W = zeros(N + 1, N + 1)
    W_m = zeros(N + 1, m)

    #---------------------------------------
    # Terminal conditions
    #---------------------------------------

    D_m1 = zeros(m + 1, m + 1)
    M = zeros(m + 1, m)

    # (1) Constuct the D_{m+1} matrix using the formula

    for j in 1:(m+1)
        for k in j:(m+1)
            D_m1[j, k] = (d[1:j,1]' * d[k-j+1:k,1])[1]
        end
    end

    # Make the matrix symmetric
    D_m1 = D_m1 + D_m1' - diagm(diag(D_m1))

    # (2) Construct the M matrix using the entries of D_m1

    for j in 1:m
        for i in (j + 1):(m + 1)
            M[i, j] = D_m1[i-j, m+1]
        end
    end
    M

    #----------------------------------------------
    # Euler equations for t = 0, 1, ..., N-(m+1)
    #----------------------------------------------
    phi, h = lqf.phi, lqf.h

    W[1:(m + 1), 1:(m + 1)] = D_m1 + h * eye(m + 1)
    W[1:(m + 1), (m + 2):(2m + 1)] = M

    for (i, row) in enumerate((m + 2):(N + 1 - m))
        W[row, (i + 1):(2m + 1 + i)] = phi'
    end

    for i in 1:m
        W[N - m + i + 1 , end-(2m + 1 - i)+1:end] = phi[1:end-i]
    end

    for i in 1:m
        W_m[N - i + 2, 1:(m - i)+1] = phi[(m + 1 + i):end]
    end

    return W, W_m
end


"""
This function calculates z_0 and the 2m roots of the characteristic equation
associated with the Euler equation (1.7)
Note:
------
`poly(roots)` from Polynomial.jll defines a polynomial using its roots that can be
evaluated at any point by `polyval(Poly,x)`. If x_1, x_2, ... , x_m are the roots then
    polyval(poly(roots),x) = (x - x_1)(x - x_2)...(x - x_m)
"""
function roots_of_characteristic(lqf::LQFilter)
    m, phi = lqf.m, lqf.phi
    
    # Calculate the roots of the 2m-polynomial
    phi_poly=Poly(phi[end:-1:1])
    proots = roots(phi_poly)
    # sort the roots according to their length (in descending order)
    roots_sorted = sort(proots, by=abs)[end:-1:1]
    z_0 = sum(phi) / polyval(poly(proots),1.0)
    z_1_to_m = roots_sorted[1:m]     # we need only those outside the unit circle
    lambdas = 1 ./ z_1_to_m
    return z_1_to_m, z_0, lambdas
end

"""
This function computes the coefficients {c_j, j = 0, 1, ..., m} for
    c(z) = sum_{j = 0}^{m} c_j z^j
Based on the expression (1.9). The order is
    c_coeffs = [c_0, c_1, ..., c_{m-1}, c_m]
"""
function coeffs_of_c(lqf::LQFilter)
    m = lqf.m
    z_1_to_m, z_0, lambdas = roots_of_characteristic(lqf)
    c_0 = (z_0 * prod(z_1_to_m) * (-1.0)^m)^(0.5)
    c_coeffs = coeffs(poly(z_1_to_m)) * z_0 / c_0
    return c_coeffs
end

"""
This function calculates {lambda_j, j=1,...,m} and {A_j, j=1,...,m}
of the expression (1.15)
"""
function solution(lqf::LQFilter)
    z_1_to_m, z_0, lambdas = roots_of_characteristic(lqf)
    c_0 = coeffs_of_c(lqf)[end]
    A = zeros(lqf.m)
    for j in 1:m
        denom = 1 - lambdas/lambdas[j]
        A[j] = c_0^(-2) / prod(denom[1:m .!= j])
    end
    return lambdas, A
end

"""
This function constructs the covariance matrix for x^N (see section 6)
for a given period N
"""
function construct_V(lqf::LQFilter; N=nothing)
    if N == nothing
        error("N must be provided!!")
    end
    if !(typeof(N) <: Integer)
        throw(ArgumentError("N must be Integer!"))
    end
        
    phi_r, k = lqf.phi_r, lqf.k
    V = zeros(N, N)
    for i in 1:N
        for j in 1:N
            if abs(i-j) <= k
                V[i, j] = phi_r[k + abs(i-j)+1]
            end
        end
    end
    return V
end

"""
Assuming that the u's are normal, this method draws a random path
for x^N
"""
function simulate_a(lqf::LQFilter, N::Integer)
    V = construct_V(N + 1)
    d = MVNSampler(zeros(N + 1), V)
    return rand(d)
end

"""
This function implements the prediction formula discussed is section 6 (1.59)
It takes a realization for a^N, and the period in which the prediciton is formed

Output:  E[abar | a_t, a_{t-1}, ..., a_1, a_0]
"""
function predict(lqf::LQFilter, a_hist::Vector, t::Integer)
    N = length(a_hist) - 1
    a_hist = a_hist''
    V = construct_V(N + 1)

    aux_matrix = zeros(N + 1, N + 1)
    aux_matrix[1:t+1 , 1:t+1 ] = eye(t + 1)
    L = chol(V)'
    Ea_hist = inv(L) * aux_matrix * L * a_hist

    return Ea_hist
end


"""
- if t is NOT given it takes a_hist (Vector or Array) as a deterministic a_t
- if t is given, it solves the combined control prediction problem (section 7)
　(by default, t == nothing -> deterministic)

for a given sequence of a_t (either determinstic or a particular realization),
it calculates the optimal y_t sequence using the method of the lecture

Note:
------
lufact normalizes L, U so that L has unit diagonal elements
To make things cosistent with the lecture, we need an auxiliary diagonal
matrix D which renormalizes L and U
"""

function optimal_y(lqf, a_hist, t = nothing )
    beta, y_m, m = lqf.beta, lqf.y_m, lqf.m

    N = length(a_hist) - 1
    W, W_m = construct_W_and_Wm(lqf, N)

    F = lufact(W, Val{true})

    L, U = F[:L], F[:U]
    D = diagm(1.0./diag(U))
    U = D * U
    L = L * diagm(1.0./diag(D))

    J = flipdim(eye(N + 1), 2)

    if t == nothing   # if the problem is deterministic
        a_hist = J * a_hist''

        #--------------------------------------------
        # Transform the a sequence if beta is given
        #--------------------------------------------
        if beta != 1
            a_hist =  reshape(a_hist * (beta^(collect(N:0)/ 2)),N + 1, 1)
        end

        a_bar = a_hist - W_m * y_m           # a_bar from the lecutre
        Uy = \(L, a_bar)            # U @ y_bar = L^{-1}a_bar from the lecture
        y_bar = \(U, Uy)            # y_bar = U^{-1}L^{-1}a_bar
        # Reverse the order of y_bar with the matrix J
        J = flipdim(eye(N + m + 1), 2)
        y_hist = J * vcat(y_bar, y_m)     # y_hist : concatenated y_m and y_bar
        #--------------------------------------------
        # Transform the optimal sequence back if beta is given
        #--------------------------------------------
        if beta != 1
            y_hist = y_hist .* beta.^(- collect(-m:N)/2)
        end

    else           # if the problem is stochastic and we look at it
        Ea_hist = reshape(predict(a_hist, t), N + 1, 1)
        Ea_hist = J * Ea_hist

        a_bar = Ea_hist - W_m * y_m           # a_bar from the lecutre
        Uy = \(L, a_bar)            # U @ y_bar = L^{-1}a_bar from the lecture
        y_bar = \(U, Uy)            # y_bar = U^{-1}L^{-1}a_bar

        # Reverse the order of y_bar with the matrix J
        J = flipdim(eye(N + m + 1), 2)
        y_hist = J * vcat(y_bar, y_m)     # y_hist : concatenated y_m and y_bar
    end
    return y_hist, L, U, y_bar
end
