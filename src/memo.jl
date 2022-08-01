
#
# functions for filling the submatch vector
#

submatch_start(st::ParserState) = length(st.submatches) + 1

const submatch_empty = submatch_start

function submatch_record!(st::ParserState, mid::Int)
    push!(st.submatches, mid)
    length(st.submatches)
end

function submatch_record!(st::ParserState, mid1::Int, mid2::Int)
    push!(st.submatches, mid1)
    ret = length(st.submatches)
    push!(st.submatches, mid2)
    ret
end

submatch_rollback!(st::ParserState, start::Int) = resize!(st.submatches, start - 1)

function submatches(st::ParserState, mid::Int)
    b = st.matches[mid].submatches
    if b == 0 || b > length(st.submatches)
        return view(st.submatches, 1:0)
    end
    e = mid < length(st.matches) ? st.matches[mid+1].submatches - 1 : length(st.submatches)
    view(st.submatches, b:e)
end

#
# splaytree operations for the memo table
#

function adjust_match!(st::ParserState, mid::Int; kwargs...)
    st.matches[mid] = Match(st.matches[mid]; kwargs...)
    nothing
end

function adjust_child!(st::ParserState, mid::Int, old::Int, new::Int)
    if mid == 0
        st.memo_root = new
        return
    end

    m = st.matches[mid]
    if m.left == old
        adjust_match!(st, mid, left = new)
    elseif m.right == old
        adjust_match!(st, mid, right = new)
    else
        error("child missed!")
    end
end

function adjust_parent!(st::ParserState, mid::Int, new::Int)
    mid == 0 && return
    adjust_match!(st, mid, parent = new)
end

function match_splay!(st::ParserState, mid::Int)
    while true
        m = st.matches[mid]

        m.parent == 0 && break

        pid = m.parent
        p = st.matches[pid]

        if mid == p.left
            # left child
            if p.parent == 0
                adjust_match!(st, mid, right = pid, parent = 0)
                adjust_match!(st, pid, left = m.right, parent = mid)
                adjust_parent!(st, m.right, pid)
                break
            end
            ppid = p.parent
            pp = st.matches[ppid]
            if m.parent == pp.left
                # left of left
                adjust_child!(st, pp.parent, ppid, mid)
                adjust_match!(st, mid, parent = pp.parent, right = pid)
                adjust_match!(st, pid, parent = mid, left = m.right, right = ppid)
                adjust_match!(st, ppid, parent = pid, left = p.right)
                adjust_parent!(st, m.right, pid)
                adjust_parent!(st, p.right, ppid)
            else
                # left of right
                adjust_child!(st, pp.parent, ppid, mid)
                adjust_match!(st, mid, parent = pp.parent, left = ppid, right = pid)
                adjust_match!(st, pid, parent = mid, left = m.right)
                adjust_match!(st, ppid, parent = mid, right = m.left)
                adjust_parent!(st, m.right, pid)
                adjust_parent!(st, m.left, ppid)
            end
        else
            # right child
            if p.parent == 0
                adjust_match!(st, mid, left = pid, parent = 0)
                adjust_match!(st, pid, right = m.left, parent = mid)
                adjust_parent!(st, m.left, pid)
                break
            end
            ppid = p.parent
            pp = st.matches[ppid]
            if m.parent == pp.left
                # right of left
                adjust_child!(st, pp.parent, ppid, mid)
                adjust_match!(st, mid, parent = pp.parent, right = ppid, left = pid)
                adjust_match!(st, pid, parent = mid, right = m.left)
                adjust_match!(st, ppid, parent = mid, left = m.right)
                adjust_parent!(st, m.left, pid)
                adjust_parent!(st, m.right, ppid)
            else
                # right of right
                adjust_child!(st, pp.parent, ppid, mid)
                adjust_match!(st, mid, parent = pp.parent, left = pid)
                adjust_match!(st, pid, parent = mid, right = m.left, left = ppid)
                adjust_match!(st, ppid, parent = pid, right = p.left)
                adjust_parent!(st, m.left, pid)
                adjust_parent!(st, p.left, ppid)
            end
        end
    end

    st.memo_root = mid
end

function match_insert!(st::ParserState, nmid::Int)
    nm = st.matches[nmid]

    @assert nm.left == 0
    @assert nm.right == 0
    @assert nm.parent == 0

    if st.memo_root == 0
        st.memo_root = nmid
        return
    end

    mid = st.memo_root
    while true
        m = st.matches[mid]
        if nm.pos < m.pos || (nm.pos == m.pos && nm.clause > m.clause)
            if m.left == 0
                # append left
                adjust_match!(st, nmid, parent = mid)
                adjust_match!(st, mid, left = nmid)
                match_splay!(st, nmid)
                return
            else
                # continue left
                mid = m.left
            end
        elseif nm.pos > m.pos || (nm.pos == m.pos && nm.clause < m.clause)
            if m.right == 0
                # append right
                adjust_match!(st, nmid, parent = mid)
                adjust_match!(st, mid, right = nmid)
                match_splay!(st, nmid)
                return
            else
                # continue right
                mid = m.right
            end
        else
            # replace
            adjust_match!(st, nmid, parent = m.parent, left = m.left, right = m.right)

            # adjust environs
            adjust_child!(st, m.parent, mid, nmid)
            adjust_parent!(st, m.left, nmid)
            adjust_parent!(st, m.right, nmid)

            # disconnect the old match
            adjust_match!(st, mid, parent = 0, left = 0, right = 0)

            match_splay!(st, nmid)
            return
        end
    end
end

function match_find!(st::ParserState, clause::Int, pos::Int)::MatchResult
    mid = st.memo_root
    mid == 0 && return 0
    while true
        m = st.matches[mid]
        if pos == m.pos && clause == m.clause
            match_splay!(st, mid)
            return mid
        end

        nmid = pos < m.pos || (pos == m.pos && clause > m.clause) ? m.left : m.right
        if nmid == 0
            match_splay!(st, mid)
            return 0
        end

        mid = nmid
    end
end
