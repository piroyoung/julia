module Threading

export threadid, maxthreads, nthreads, @threads

threadid() = int(ccall(:jl_threadid, Int16, ())+1)
maxthreads() = int(unsafe_load(cglobal(:jl_max_threads, Cint)))
nthreads() = int(unsafe_load(cglobal(:jl_n_threads, Cint)))

function _threadsfor(forexpr)
    fun = gensym("_threadsfor")
    lidx = forexpr.args[1].args[1]			# index
    st = lst = forexpr.args[1].args[2].args[1]		# start
    len = llen = forexpr.args[1].args[2].args[2]	# length
    lbody = forexpr.args[2]				# body
    quote
	function $fun()
	    tid = threadid()
	    # divide loop iterations among threads
	    len, rem = divrem($llen, nthreads())
            # not enough iterations for all the threads?
            if len == 0
                if tid > rem
                    return
                end
                len, rem = 1, 0
            end
            # compute this thread's range
	    st = $lst + ((tid-1) * len)
            # distribute remaining iterations evenly
	    if rem > 0
		if tid <= rem
		    st = st + (tid-1)
		    len = len + 1
		else
		    st = st + rem
		end
	    end
            # run this thread's iterations
	    for $(esc(lidx)) = range(st, len)
		$(esc(lbody))
	    end
	end
        ccall(:jl_threading_run, Void, (Any, Any), $fun, ())
    end
end

function _threadsblock(blk)
    fun = gensym("_threadsblock")
    esc(quote
        function $fun()
            $blk
        end
        ccall(:jl_threading_run, Void, (Any, Any), $fun, ())
    end)
end

function _threadscall(callexpr)
    fun = callexpr.args[1]
    esc(quote
        ccall(:jl_threading_run, Void, (Any, Any), $fun, $(Expr(:tuple, callexpr.args[2:end]...)))
    end)
end

macro threads(args...)
    na = length(args)
    if na != 2
        throw(ArgumentError("wrong number of arguments in @threads"))
    end
    tg = args[1]
    if !is(tg, :all)
        throw(ArgumentError("only 'all' supported as thread group for @threads"))
    end
    ex = args[2]
    if !isa(ex, Expr)
	throw(ArgumentError("need an expression argument to @threads"))
    end
    if is(ex.head, :for)
	return _threadsfor(ex)
    elseif is(ex.head, :block)
	return _threadsblock(ex)
    elseif is(ex.head, :call)
	return _threadscall(ex)
    else
        throw(ArgumentError("unrecognized argument to @threads"))
    end
end

end # module
