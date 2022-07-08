
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

function adjust_child!(st::ParserState, mid::Int, old::Int, new::Int)
    if mid == 0
        st.memo_root = new
        return
    end

    m = st.matches[mid]
    if m.left == old
        m.left = new
    elseif m.right == old
        m.right = new
    else
        error("child missed!")
    end
    nothing
end

function adjust_parent!(st::ParserState, mid::Int, new::Int)
    mid == 0 && return
    st.matches[mid].parent = new
    nothing
end

function match_splay!(st::ParserState, mid::Int)
    m = st.matches[mid]

    while true
        #@info "splay" mid m
        m.parent == 0 && break

        pid = m.parent
        p = st.matches[pid]
        #@info "parent" pid p

        if mid == p.left
            # left child
            if p.parent == 0
                adjust_parent!(st, m.right, pid)
                p.left = m.right
                m.right = pid
                p.parent = mid
                m.parent = 0
                #@info "L" mid m pid p
                break
            end
            ppid = p.parent
            pp = st.matches[ppid]
            #@info "L pparent" pp
            if m.parent == pp.left
                # left of left
                a = m.right
                b = p.right
                adjust_child!(st, pp.parent, ppid, mid)
                m.parent = pp.parent
                m.right = pid
                p.parent = mid
                p.left = a
                adjust_parent!(st, a, pid)
                p.right = ppid
                pp.parent = pid
                pp.left = b
                adjust_parent!(st, b, ppid)
                #@info "LL" mid m pid p ppid pp
            else
                # left of right
                a = m.left
                b = m.right
                adjust_child!(st, pp.parent, ppid, mid)
                m.parent = pp.parent
                m.right = pid
                p.parent = mid
                p.left = b
                adjust_parent!(st, b, pid)
                m.left = ppid
                pp.parent = mid
                pp.right = a
                adjust_parent!(st, a, ppid)
                #@info "LR" mid m pid p ppid pp
            end
        else
            # right child
            if p.parent == 0
                adjust_parent!(st, m.left, pid)
                p.right = m.left
                m.left = pid
                p.parent = mid
                m.parent = 0
                #@info "R" mid m pid p
                break
            end
            ppid = p.parent
            pp = st.matches[ppid]
            #@info "R pparent" pp
            if m.parent == pp.left
                # right of left
                a = m.left
                b = m.right
                adjust_child!(st, pp.parent, ppid, mid)
                m.parent = pp.parent
                m.left = pid
                p.parent = mid
                p.right = a
                adjust_parent!(st, a, pid)
                m.right = ppid
                pp.parent = mid
                pp.left = b
                adjust_parent!(st, b, ppid)
                #@info "RL" mid m pid p ppid pp
            else
                # right of right
                a = m.left
                b = p.left
                adjust_child!(st, pp.parent, ppid, mid)
                m.parent = pp.parent
                m.left = pid
                p.parent = mid
                p.right = a
                adjust_parent!(st, a, pid)
                p.left = ppid
                pp.parent = pid
                pp.right = b
                adjust_parent!(st, b, ppid)
                #@info "RR" mid m pid p ppid pp
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

    #@info "insert" nmid nm

    if st.memo_root == 0
        st.memo_root = nmid
        return
    end

    mid = st.memo_root
    while true
        m = st.matches[mid]
        #@info "inserting" mid m
        if nm.pos < m.pos || (nm.pos == m.pos && nm.clause > m.clause)
            if m.left == 0
                # append left
                nm.parent = mid
                m.left = nmid
                match_splay!(st, nmid)
                return
            else
                # continue left
                mid = m.left
            end
        elseif nm.pos > m.pos || (nm.pos == m.pos && nm.clause < m.clause)
            if m.right == 0
                # append right
                nm.parent = mid
                m.right = nmid
                match_splay!(st, nmid)
                return
            else
                # continue right
                mid = m.right
            end
        else
            # replace
            nm.parent = m.parent
            nm.left = m.left
            nm.right = m.right

            # adjust environs
            adjust_child!(st, m.parent, mid, nmid)
            adjust_parent!(st, m.left, nmid)
            adjust_parent!(st, m.right, nmid)

            # disconnect the old match
            m.parent = 0
            m.left = 0
            m.right = 0

            match_splay!(st, nmid)
            return
        end
    end
end

function match_find!(st::ParserState, clause::Int, pos::Int)::MatchResult
    mid = st.memo_root
    mid == 0 && return nothing
    while true
        #@info "find" mid
        m = st.matches[mid]
        if pos == m.pos && clause == m.clause
            match_splay!(st, mid)
            return mid
        end

        nmid = pos < m.pos || (pos == m.pos && clause > m.clause) ? m.left : m.right
        if nmid == 0
            match_splay!(st, mid)
            return nothing
        end

        mid = nmid
    end
end
