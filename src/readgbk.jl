function parseheader(header::String)
    lines = split(header, "\n")
    locus = split(lines[1], r" +")[2]
    return locus
end

# function parseposition(line::String)
#     feature, position = split(strip(line), r" +")
#     complement = occursin("complement", position)::Bool
#     complete = !occursin(r"[<>]", position)::Bool
#     position = parse.(Int, filter.(c->isnumeric(c), split(position, r"\.\.(.*\.\.)?")))
#     return (feature, position[1]:position[2], complement, complete)
# end


"""
Parse lines encoding genomic position, returning the feature as a `String`, and an instance of `Locus`.
"""
function parseposition(line::String)
    feature, posstring = split(strip(line), r" +")
    if occursin("..", posstring)
        position = UnitRange(parse.(Int, filter.(c->isnumeric(c), split(posstring, r"\.\.(.*\.\.)?")))...)
        strand = occursin("complement", posstring) ? '-' : '+'
    else
        strand = '.'
    end
    complete_left = !occursin('<', posstring)
    complete_right = !occursin('>', posstring)
    if occursin("order", posstring)
        @warn "Loci with breaks in them have not yet been implemented"
    end
    excluding = Vector{UnitRange{Int}}()
    return feature, Locus(position, strand, complete_left, complete_right, excluding)
end


"""
Parse footer (sequence) portion of a GenBank file, returning a `String`. When `BioSequences` is available for 0.7 this will be changed to a `DNASequence`.
"""
function filterseq(io::IOBuffer)
    line = String(take!(io))
    String(replace(filter(x -> !(isspace(x) || isnumeric(x)), line), r"[^ATGCNatgcn]" => "n"))
end


"""
    parsechromosome(lines)

Parse and return one chromosome entry, and the line number that it ends at.
"""
function parsechromosome(lines)
    genes = Gene[]
    # genomename = basename(filename)[1:(end-4)]
    iobuffer = IOBuffer()
	isheader = true
    isfooter = false
    spanning = false
    position_spanning = false
    qualifier = String("")
    content = String("")
    header = ""

    feature = ""
    locus = Locus()

    chromosome = Chromosome()

    linecount = 0
	# fstream = open(filename)
    # @assert eof(fstream) == false
	# for line in eachline(fstream)
    for line in lines
        linecount += 1

        # Catch cases where there's no header
        if linecount == 1 && occursin(r"gene", line)
            isheader = false
        end

        ### HEADER
		if isheader && occursin(r"FEATURES", line)
			isheader = false

        elseif isheader
            header *= linecount == 1 ? "$line" : "\n$line"

        # Check if the footer has been reached
		elseif !isheader && !isfooter && (occursin(r"^BASE COUNT", line) || occursin(r"ORIGIN", line))
			# Stop parsing the file when the list of genes is over
            isheader = false
            isfooter = true
			iobuffer = IOBuffer()

        ### BODY
		elseif !isheader && !isfooter
            if position_spanning && occursin(r"  /", line)
                position_spanning = false
                spanningline = filter(x -> x != ' ', String(take!(iobuffer)))
                try
                    feature, locus = parseposition(spanningline)
                catch
                    println(spanningline)
                    println(line)
                    @error "parseposition(spanningline) failed at line $linecount"
                end
            elseif position_spanning
                print(iobuffer, line)
            end
            if occursin(r"^ {5}\S", line)
                spanning = false
                try
                    feature, locus = parseposition(line)
                catch
                    println(line)
                    @error "parseposition(line) failed at line $linecount"
                end
                addgene!(chromosome, feature, locus)
            elseif !spanning && occursin(r"^ +/", line)
                if occursin(r"=", line)
                    if occursin("=\"", line)
                        (qualifier, content) = match(r"^ +/([^=]+)=\"?([^\"]*)\"?$", line).captures
                        content = String(content)
                    else
                        (qualifier, content) = match(r"^ +/(\S+)=(\S+)$", line).captures
                        try
                            content = Meta.parse(Int, content)
                        catch
                            content = Symbol(content)
                        end
                    end

                    if occursin(r"\".*[^\"]$", line)
                        spanning = true
                    end

                    # Base.setproperty!(chromosome.genes[end], Symbol(qualifier), content)
                    pushproperty!(chromosome.genes[end], Symbol(qualifier), content)

                else
                    # Qualifiers without a value assigned to them end up here
                    qualifier = split(line, '/')[2]
                    pushproperty!(chromosome.genes[end], Symbol(qualifier), true)
                end
            elseif spanning
                try
                    content = match(r" {21}([^\"]*)\"?$", line)[1]
                catch
                    @warn "Couldn't read content"
                end
                if line[end] == '"'
                    spanning = false
                end
                if eltype(chromosome.genedata[Symbol(qualifier)]).b <: AbstractArray
                    i = chromosome.genes[end].index
                    chromosome.genedata[Symbol(qualifier)][end][end] = Base.getproperty(chromosome.genes[end], Symbol(qualifier))[end] * "\n" * content
                else
                    Base.setproperty!(chromosome.genes[end], Symbol(qualifier), Base.getproperty(chromosome.genes[end], Symbol(qualifier)) * "\n" * content)
                end
            end

        ### FOOTER
        elseif isfooter
            if line == "//"
                break
            end
            if occursin(r"^ ", line)
                print(iobuffer, line)
            end
        end
    end
    chromosome.name = parseheader(header)
    chromosome.sequence = filterseq(iobuffer)
    chromosome.header = header
    return linecount, chromosome
end


"""
    readgbk(filename)

Parse GenBank-formatted file `filename`, returning a `Chromosome`.
"""
function readgbk(filename::String = "/seq/LAB/kunkeei_genomes_new/genbanks/with_rRNAs/A00901.gbk")
    finished = false
    chrs = Chromosome[]
    lines = readlines(filename)
    currentline = 1
    while !finished
        if currentline >= length(lines)
            break
        end
        i, chr = parsechromosome(lines[currentline:end])
        currentline += i
        push!(chrs, chr)
    end
    return chrs
end
