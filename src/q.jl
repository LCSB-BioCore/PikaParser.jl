
#
# A very specialized heap-based constant-size queue
#

PikaQueue(n::Int) = PikaQueue(0, Vector{UInt}(undef, n), fill(false, n))

Base.isempty(q::PikaQueue) = q.n == 0

full_queue(n::Int) = PikaQueue(n, UInt.(1:n), fill(true, n))

function reset!(q::PikaQueue, sorted_vals::Vector{Int})
    q.n = length(sorted_vals)
    q.q[1:q.n] .= sorted_vals
    q.p .= false
    for i in sorted_vals
        q.p[i] = true
    end
end

function reset!(q::PikaQueue, q2::PikaQueue)
    q.n = q2.n
    q.q .= q2.q
    q.p .= q2.p
end

function swap!(q::PikaQueue, i::UInt, j::UInt)
    tmp = q.q[i]
    q.q[i] = q.q[j]
    q.q[j] = tmp
    nothing
end

function Base.pop!(q::PikaQueue)
    ret = q.q[1]
    q.q[1] = q.q[q.n]
    q.n -= 1
    q.p[ret] = false

    # bubble down
    i = UInt(1)
    while true
        L = 2 * i
        R = L + 1
        if R <= q.n
            l = q.q[L]
            r = q.q[R]
            if l < r
                q.q[i] <= l && break
                swap!(q, i, L)
                i = L
            else
                q.q[i] <= r && break
                swap!(q, i, R)
                i = R
            end
            continue
        elseif L <= q.n
            q.q[i] > q.q[L] && swap!(q, i, L)
        end
        break
    end

    return Int(ret)
end

function Base.push!(q::PikaQueue, x::Int)
    q.p[x] && return
    q.p[x] = true
    q.n += 1
    q.q[q.n] = x

    i = q.n

    # bubble up
    while i > 1
        P = i >> 1
        q.q[P] < q.q[i] && break
        swap!(q, P, i)
        i = P
    end
end
