#!/bin/bash
export PATH=$PATH:/users/bi/jlimberis/bin/cufflinks-2.2.1.Linux_x86_64
export PATH=$PATH:/users/bi/jlimberis/bin
export PATH=$PATH:/users/bi/jlimberis/bin/bedtools2/bin
export PATH=$PATH:/users/bi/jlimberis/bin/bcftools-1.3.1
export PATH=$PATH:/users/bi/jlimberis/bin/FastQC
export PATH=$PATH:/users/bi/jlimberis/bin/htslib-1.3.2
export PATH=$PATH:/users/bi/jlimberis/bin/STAR-2.5.2b/bin/Linux_x86_64
export PATH=$PATH:/users/bi/jlimberis/bin/subread-1.5.1-Linux-x86_64/bin
export PATH=$PATH:/users/bi/jlimberis/bin/HTSeq-0.6.1/scripts

TRIM=~/bin/trimmomatic.jar
adapterSE=~/bin/Trimmomatic/adapters/TruSeq2-SE.fa
adapterPE=~/bin/Trimmomatic/adapters/TruSeq2-PE.fa
PICARD=~/bin/picard.jar
vc="F" # untested
GATK="~/bin/GATK/gatk.jar"
Script_dir=$(dirname "$0")

#check if programs installed
command -v cufflinks >/dev/null 2>&1 || { echo >&2 "I require cufflinks but it's not installed. Aborting."; exit 1; }
command -v bedtools >/dev/null 2>&1 || { echo >&2 "I require bedtools but it's not installed. Aborting."; exit 1; }
command -v bcftools >/dev/null 2>&1 || { echo >&2 "I require bcftools but it's not installed. Aborting."; exit 1; }
command -v fastqc >/dev/null 2>&1 || { echo >&2 "I require fastqc but it's not installed. Aborting."; exit 1; }
command -v samtools >/dev/null 2>&1 || { echo >&2 "I require samtools but it's not installed. Aborting."; exit 1; }
command -v STAR >/dev/null 2>&1 || { echo >&2 "I require STAR but it's not installed. Aborting."; exit 1; }
command -v htseq-count >/dev/null 2>&1 || { echo >&2 "I require htseq but it's not installed. Aborting."; exit 1; }
command -v python >/dev/null 2>&1 || { echo >&2 "I require python2.* but it's not installed. Aborting."; exit 1; }
command -v featureCounts >/dev/null 2>&1 || { echo >&2 "I require featureCounts but it's not installed. Aborting."; exit 1; }
command -v bowtie2 >/dev/null 2>&1 || { echo >&2 "I require bowtie2 but it's not installed. Aborting."; exit 1; }
if [ ! -f "$TRIM" ]; then echo "$TRIM not found!"; exit 1; fi
if [ ! -f "$PICARD" ]; then echo "$PICARD not found!"; exit 1; fi

if [ $# == 0 ]
  then
    echo -e "Usage: ./RNA_processes.sh Input_paramaters.txt threads ram \n
    if indexing a genome for the first time, this will require >30GB ram for a human genome\n"
    echo -e "Input_paramaters.txt should be a comma seperated list conatining the following:\n
    the directory where the file(s) are, the output name, the output directory, the fastq file, \n
    the second fastq file if PE reads - else leave blank (i.e fiel1,,outdir) \n
    full path to the genome to align to first, the genome to align reads not aligned to genome 1 - if desired, \n
    genome1 E=eukaryotic, B=bacterial, genome2 E=eukaryotic, B=bacterial \n
    gtf/gff genome1, gtf/gff genome 2 \n
    Stranded library yes|no|reverse"
    exit 1
fi
#/users/bi/jlimberis/CASS_RNAseq,C100,/users/bi/jlimberis/RNAseqData,C100_GTAGAG_HS374-375-376-merged_R1_001.fastq.gz,,/users/bi/jlimberis/testing/Homo_sapiens.GRCh38.dna.primary_assembly.fa,/users/bi/jlimberis/testing/GCF_000195955.2_ASM19595v2_genomic.fna,E,B,/users/bi/jlimberis/testing/Homo_sapiens.GRCh38.87.gtf,/users/bi/jlimberis/testing/GCF_000195955.2_ASM19595v2_genomic.gff



# Define fucntions
#QC and trim of data
		#Remove adapters
		#Remove leading low quality or N bases (below quality 3)
		#Remove trailing low quality or N bases (below quality 3)
		#Scan the read with a 3-base wide sliding window, cutting when the average quality per base drops below 15
		#Drop reads below the 30 bases long


get_reference () {
  mkdir "${Script_dir}/references" #wont overwrite so its ok
  if [[ ! -e $1 ]]
  then
    if [[ ! -e "${Script_dir}/references/$(basename $1).fasta" ]]
    then
        echo "Downloading reference genome $(basename $1)"
        curl "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=$(basename $1)&rettype=fasta" > "${Script_dir}/references/$(basename $1).fasta"
        export ${2}="${Script_dir}/references/$(basename $1).fasta"
    else
        export ${2}="${Script_dir}/$(basename $1).fasta"
        echo "Found reference genome file for $(basename $1)"
    fi
  else
    echo "Found reference genome file for $(basename $1)"
  fi

  if [[ ! -e $3 ]]
  then
    if [[ ! -e "${Script_dir}/references/$(basename $3).gtf" ]]
    then
        curl "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=$(basename $1)&rettype=gtf" > "${Script_dir}/references/$(basename $3).gtf"
        export ${4}="${Script_dir}/references/$(basename $3).gtf"
    else
        export ${4}="${Script_dir}/references/$(basename $3).gtf"
        echo "Found annotations for genome file for $(basename $3)"
    fi
  else
    echo "Found reference genome file for $(basename $1)"
  fi
}

qc_trim_SE () {
  #FastQC pre
  fastqc -t $3 "$1" -o "$2"

  if [[ $trim == "Y" ]]
  then
      if [[ -e "${1/.f*/.trimmed.fq.gz}" ]]
      then
          echo "Found ${1/f*/forward.fq.gz}"
      else
          #Trim Reads
          echo "trimming started $1"
          # java -Xmx"${3}"g -jar ~/bin/trimmomatic.jar SE -phred33 \
          java -jar "$TRIM" SE -phred33 \
            -threads $4 \
            "$1" \
            "${1/.f*/.trimmed.fq.gz}" \
            ILLUMINACLIP:"$adapterSE":2:30:10 LEADING:2 TRAILING:2 SLIDINGWINDOW:4:10 MINLEN:20

          #FastQC post
          fastqc -t $3 "${1/.f*/.trimmed.fq.gz}" -o "$2"
      fi
  else
      #cheecky workaround after i had alreay written for trmming, this copys the file unnecessarily, will make it better sometime
      cp "$1" "${1/.f*/.trimmed.fq.gz}"

  fi

  echo "trimming completed"


    # if [[ $trim != "Y" ]] && [[ ${#adapterSE} -gt 0 || ${#adapterPE} -gt 0 ]]
    # then
    #
    # fi
}

qc_trim_PE () {
  #FastQC pre
  fastqc -t $3 "$1" -o "$3"
  fastqc -t $3 "$2" -o "$3"

  #Trim Reads
  echo "trimming started $1 $2"
  if [[ $trim == "Y" ]]
  then
      if [[ -e "${1/f*/forward.fq.gz}" ]]
      then
        echo "Found ${1/f*/forward.fq.gz}"
      else
          # java -Xmx"${4}"g -jar ~/bin/trimmomatic.jar PE -phred33 \
          java -jar "$TRIM" PE -phred33 \
            -threads $5 \
            "$1" "$2" \
            "${1/f*/forward_paired.fq.gz}" "${1/f*/_forward_unpaired.fq.gz}" \
        		"${2/f*/_reverse_paired.fq.gz}" "${2/f*/_reverse_unpaired.fq.gz}" \
            ILLUMINACLIP:"$adapterPE":2:30:10 LEADING:2 TRAILING:2 SLIDINGWINDOW:4:10 MINLEN:20

          #FastQC post
          fastqc -t $3 "${1/f*/forward_paired.fq.gz}" -o "$3"
          fastqc -t $3 "${2/f*/_reverse_paired.fq.gz}" -o "$3"

          #as we also want unpaired reads so..
          cat "${1/f*/forward_paired.fq.gz}" "${1/f*/_forward_unpaired.fq.gz}" > "${1/f*/forward.fq.gz}"
        	cat "${2/f*/_reverse_paired.fq.gz}" "${2/f*/_reverse_unpaired.fq.gz}" > "${2/f*/reverse.fq.gz}"
      fi
  else
      if [[ -e "${1/f*/forward.fq.gz}" ]]
      then
        echo "Found ${1/f*/forward.fq.gz}"
      else
          #just clip adapeters
          # java -jar "$TRIM" PE -phred33 \
            # -threads $5 \
            # "$1" "$2" \
            # "${1/f*/forward_paired.fq.gz}" "${1/f*/_forward_unpaired.fq.gz}" \
        		# "${2/f*/_reverse_paired.fq.gz}" "${2/f*/_reverse_unpaired.fq.gz}" \
            # ILLUMINACLIP:"$adapterPE":2:30:10

          # cat "${1/f*/forward_paired.fq.gz}" "${1/f*/_forward_unpaired.fq.gz}" > "${1/f*/forward.fq.gz}"
        	# cat "${2/f*/_reverse_paired.fq.gz}" "${2/f*/_reverse_unpaired.fq.gz}" > "${2/f*/reverse.fq.gz}"
        	cp "$1" "${1/f*/forward.fq.gz}"
        	cp "$2" "${2/f*/reverse.fq.gz}"
      fi
  fi

	echo "trimming completed"


}

# Bowite index
BOWTIE_index () {
  #check if indexed alread
  if [ ! -e ${1/.f*/.1.bt2} ]
  then
      if [[ $1 == *.gz ]]
      then
          gunzip $1
          bowtie2-build --threads $2 ${1/.gz/} ${1/.gz/} #${1/.f*/} #$(printf $1 | cut -f 1 -d '.')
      else
          bowtie2-build --threads $2 $1 $1 #${1/.f*/} #$(printf $1 | cut -f 1 -d '.')
      fi

  else
      echo "Found bowtie2 index for $1?"
  fi
}

# STAR index
STAR_index () {
  #check if indexed alread
  if [[ ! -e "$(dirname $2)/chrLength.txt" ]]
  then
      if [[ $2 == *.gz ]]
      then
        gunzip $2
      fi

      STAR \
      --runThreadN $1 \
      --runMode genomeGenerate --genomeDir $(dirname $2) \
      --genomeFastaFiles "${2/.gz/}" \
      --sjdbGTFfile "$3" \
      --outFileNamePrefix ${2/.f*/}
      # --sjdbOverhang read_length
      #this is the readlength of the RNA data - can get it from fastqs using fastqc or awk 'NR%4 == 2 {lengths[length($0)]++} END {for (l in lengths) {print l, lengths[l]}}' fastq
  else
      echo "Found STAR index for $2?"
  fi
}

BOWTIE_aligner () {
  echo "BOWTIE alignment started $3"
  out_f="${4}/${5}.$(printf $(basename $3) | cut -f 1 -d '.').sam"

  if [[ -e "${out_f/.sam/.bam}" ]]
  then
    echo "Found ${out_f/.sam/.bam}"
  else
    bowtie2 --n-ceil L,0,0.05 --score-min L,1,-0.6 -p "$2" -x ${3/.f*/}  -U "$1" -S "$out_f" --un-gz "${4}/${5}_${gen}_Unmapped.out.mate1.fastq.gz"
    #$(3 | cut -f 1 -d '.')

    # mv "${4}/un-seqs" "${4}/${5}_${gen}_Unmapped.out.mate1.fastq.gz"

    #convert to sorted bam
    # java -Xmx"${6}"g -jar ~/bin/picard*.jar SortSam \
    java -jar "$PICARD" SortSam \
        INPUT="$out_f" \
        OUTPUT="${out_f/.sam/.bam}" \
        SORT_ORDER=coordinate \
        VALIDATION_STRINGENCY=LENIENT

    rm "$out_f"

    # Index using samtools
    # samtools index "${out_f/.sam/.bam}"

    #Mark PCR duplicates with PICARD
    #this is quite slow and not really necessary most of the time
    # java -Xmx"$6"g -jar ~/bin/picard.jar MarkDuplicates \
    #   INPUT="${out_f/.sam/.bam}" \
    #   OUTPUT="${out_f/.bam/.dedup.bam}" \
    #   VALIDATION_STRINGENCY=LENIENT \
    #   REMOVE_DUPLICATES=TRUE \
    #   ASSUME_SORTED=TRUE \
    #   M="${out_f/.bam/.dedup.bam.txt}"
  fi
  echo "BOWTIE alignment completed"
}

BOWTIE_alignerPE () {
  echo "BOWTIE alignment started $3"
  out_f="${4}/${5}.$(printf $(basename $3) | cut -f 1 -d '.').sam"

  if [[ -e "${out_f/.sam/.bam}" ]]
  then
    echo "Found ${out_f/.sam/.bam}"
  else

    bowtie2 --n-ceil L,0,0.05 --score-min L,1,-0.6 -p "$2" -x ${3/.f*/}  -1 "$1" -2 "$7" -S "$out_f" --un-gz ${4} --un-conc-gz ${4}
    #$(3 | cut -f 1 -d '.')

    gen=$(basename $3)
    mv "un-conc-mate.1" "${4}/${5}_${gen}_Unmapped.out.mate1.fastq.gz"
    mv "un-conc-mate.2" "${4}/${5}_${gen}_Unmapped.out.mate1.fastq.gz"
      # cat "un-seqs" >> xx

    #convert to sorted bam
    # java -Xmx"${6}"g -jar ~/bin/picard*.jar SortSam \
    java -jar "$PICARD" SortSam \
        INPUT="$out_f" \
        OUTPUT="${out_f/.sam/.bam}" \
        SORT_ORDER=coordinate \
        VALIDATION_STRINGENCY=LENIENT

    rm "$out_f"
  fi

  echo "BOWTIE alignment completed"
}

STAR_align () {
  echo "Star alignment started"
   out_f="${4}/${5}.$(printf $(basename $2) | cut -f 1 -d '.').bam"

  if [[ -e "$out_f" ]]
  then
    echo "Found ${out_f}"
  else

    # gtf_file=$(printf $2 | cut -f 1 -d '.')
    gtf_file="$7"
    if [[ $8 == "none" ]]; then
        read2=""
    else
        read2="$8"
    fi

    #use two pass made if intresited in novel jusctions..doubles runtime
    STAR \
        --runThreadN $1 \
        --genomeDir $(dirname $2) \
        --readFilesIn "$3" "$read2" \
        --readFilesCommand zcat \
        --outFileNamePrefix "${4}/${5}" \
        --outSAMtype BAM SortedByCoordinate \
        --outReadsUnmapped Fastx \
        --outSAMstrandField intronMotif
          # --sjdbGTFfile $gtf_file \
          # --outSAMunmapped

    rm -r "${4}/${5}_STARtmp"
    gen=$(basename $2)
    mv "${4}/${5}Unmapped.out.mate1" "${4}/${5}_${gen}_Unmapped.out.mate1.fastq"
    bgzip "${4}/${5}_${gen}_Unmapped.out.mate1.fastq"
    mv "${4}/${5}Unmapped.out.mate2" "${4}/${5}_${gen}_Unmapped.out.mate2.fastq"
    bgzip "${4}/${5}_${gen}_Unmapped.out.mate2.fastq"

    mv "${4}/${5}Aligned.sortedByCoord.out.bam" "$out_f"
  fi
  #Index using samtools
  # samtools index "$out_f"

  #Mark PCR duplicates with PICARD
  # java -Xmx"$6"g -jar ~/bin/picard*.jar MarkDuplicates \
  #   INPUT= "$out_f" \
  #   OUTPUT="${out_f/.bam/.dedup.bam}" \
  #   VALIDATION_STRINGENCY=LENIENT \
  #   REMOVE_DUPLICATES=TRUE \
  #   ASSUME_SORTED=TRUE \
  #   M="${out_f/.bam/.dedup.bam.txt}"
  echo "STAR alignment completed"
}

# HISAT_align () {
  # HISAT2 -o "$2" -p $4 --no-coverage-search  $3 "$1"
# }

do_calcs () {
  # gtf_in="$(printf $2 | cut -f 1 -d '.').gtf"
  cullfinks="no"
  if [[ $cullfinks == "yes" ]]
  then
    echo "Cufflinks started $4"
    #Cufflinks
    if [[ $read2 == "none" ]]
    then
        cufflinks -q -p $5 -o "$1" -m $7 -g "$4" "$3"
        #-m is average fragment length - ie. for unpaired reads only
    else
        cufflinks -q -p $5 -o "$1" -g "$4" "$3"
    fi

    #CuffQuant to ref
    cuffquant -q -p $5 -o "$1" "$4" "$3"

    #echo "seqname	source	feature	start	end	score	strand	frame	attributes" > "${read_file}.transcripts.gtf"
    #grep exon transcripts.gtf >> "${read_file}.exon.transcripts.gtf"

      #rename files
      mv "${1}/abundances.cxb" "${3/.bam/.abundances.cxb}"
      mv "${1}/genes.fpkm_tracking" "${3/.bam/.genes.fpkm_tracking}"
      mv "${1}/isoforms.fpkm_tracking" "${3/.bam/.isoforms.fpkm_tracking}"
      mv "${1}/skipped.gtf" "${3/.bam/.skipped.gtf}"
      mv "${1}/transcripts.gtf" "${3/.bam/.transcripts.gtf}"
      echo "Cufflinks completed"

  fi

  #get some stats such as number of mapped reads
  samtools flagstat "$3" > "${3/bam/flagstat.txt}"

  #get raw counts
  echo "Counts started $4"
  if [[ $strand == "yes" ]]
  then
      strand2=1
  elif [[ $strand == "no" ]]
  then
    strand2=0
  else
    strand2=2
  fi

  if [[ $6 == "B" ]]
  then
      htseq-count --order "pos" --type "gene" -i "Name" --stranded="$stranded" -f bam "$3" "$4" > "${3/.bam/.HTSeq.counts}"
      featureCounts -t "gene" -g "Name" -O -Q 5 --ignoreDup -T $5 -a "$4" -o "${3/.bam/.featCount.counts}" "$3"
  else
      htseq-count --order "pos" --stranded="$stranded" -f bam "$3" "$4" > "${3/.bam/.HTSeq.counts}"
      featureCounts --ignoreDup -T $5 -a "$4" -o "${3/.bam/.featCount.counts}" "$3"
  fi
  echo "Counts completed"


  #can also do qualimap
  # qualimap rnaseq -bam -gtf

}


VaraintCall () {
    if [ ! -f "$GATK" ]; then
        echo "$GATK not found! Canntor run SNP calling"
    else

    #Add read groups, sort, mark duplicates, and create index
    java -jar $PICARD AddOrReplaceReadGroups \
        I="$2" \
        O="${2}.tmp.snps.bam" \
        SO=coordinate \
        RGID="id" RGLB="library" RGPL="platform" RGPU="machine" RGSM=${4}

    # Split'N'Trim and reassign mapping qualities
        java -jar $GATK \
            -T SplitNCigarReads \
            -R $1 \
            -I "${2}.tmp.snps.bam" \
            -o "${2}.split.bam" \
            -rf ReassignOneMappingQuality \
            -RMQF 255 \
            -RMQT 60 \
            -U ALLOW_N_CIGAR_READS

      rm "${2}.tmp.snps.bam"

      java -jar $PICARD BuildBamIndex \
          I="${2}.split.bam" \
          VALIDATION_STRINGENCY= LENIENT


      #Create a target list of intervals to be realigned with GATK
      java -jar $GATK \
          -T RealignerTargetCreator \
          -R $1 \
          -I "${2}.split.bam" \
          -o "${2}.split.bam.list"
      #-known indels if available.vcf

      #Perform realignment of the target intervals
      java -jar $GATK \
          -T IndelRealigner \
          -R $1 \
          -I "${2}.split.bam" \
          -targetIntervals "${2}.split.bam.list" \
          -o "${2}.tmp2.snps.bam"

        rm "${2}.split.bam"


        # Variant calling
        java -jar $GATK \
            -T HaplotypeCaller \
            -R ${1} \
            -I "${2}.tmp2.snps.bam" \
            -dontUseSoftClippedBases \
            -o "${3}/${4}.vcf"

        rm  "${2}.tmp2.snps.bam"


        #Filter - we recommend that you filter clusters of at least 3 SNPs that are within a window of 35 bases between them by adding -window 35 -cluster 3
        java -jar $GATK \
            -T VariantFiltration \
            -R ${1} \
            -V ${4}.vcf \
            -window 35 \
            -cluster 3 \
            -filterName FS \
            -filter "FS > 30.0" \
            -filterName QD \
            -filter "QD < 2.0" \
            -o "${3}/${4}_filtered.vcf"
    fi

}


#RNA pipeline from sputum - host and bacterial
# Script_dir=$(dirname "$0")
file_in="$1"
threads="$2"
ram_def=$(expr $threads \* 2)
ram="${3:-$ram_def}"
jav_ram=$(echo "scale=2; $ram*0.8" | bc)
trim="${4:-Y}" #Y|N
export _JAVA_OPTIONS=-Xmx"${jav_ram%.*}G"

while IFS=$',' read -r -a input_vars
do
    read_dir="${input_vars[0]}"
    out_dir="${input_vars[2]:-read_dir}"
    # out_dir="${input_vars[2]}"
    # name="${input_vars[1]}"
    name="${input_vars[1]:-$(basename $read1)}"
    read1="$read_dir/${input_vars[3]}"
    if [[ -z ${input_vars[4]+x} ]]; then read2="$read_dir/${input_vars[4]}"; else read2="none"; fi
    genome1="${input_vars[5]:-none}"
    genome2="${input_vars[6]:-none}"
    T1="${input_vars[7]:-E}"
    T2="${input_vars[8]:-B}"
    stranded="${input_vars[9]:-reverse}"
    f_ext="${input_vars[10]:-.fasta}"
    g_ext="${input_vars[11]:-.gbf}"


    echo "$genome2" >> "/users/bi/jlimberis/run_logs/a"
    echo "hello" >>"/users/bi/jlimberis/run_logs/a"


    mkdir "${out_dir}/${name}"
    out_dir="${out_dir}/${name}"

    if [[ $genome1 == "none" ]]; then echo "No input genome supplied!"; exit 1; fi

    #set references
    if [[ $genome1 != "none" ]]; then
        get_reference "$genome1" "genome1" "$G1" "G1"; fi
    if [[ $genome2 != "none" ]]; then
        get_reference "$genome2" "genome2" "$G2" "G2"; fi


    if [[ $genome1 != "none" ]] && [ $T1 == "E" ]
    then
        STAR_index $threads $genome1 $G1
    elif [ $genome1 != "none" ] && [ $T1 == "B" ]; then
        BOWTIE_index $genome1 $threads $G1
    fi

    if [[ $genome2 != "none" ]] && [[ $T2 == "E" ]]; then
        STAR_index $threads $genome2 $G2
    elif [[ $genome2 != "none" ]] && [[ $T2 == "B" ]]; then
        BOWTIE_index $genome2 $threads $G2
    else
      echo "Error in reference input 2"
      exit 1
    fi

    # cd "$indir"

    #QC and trim fastq files
    if [[ $read2 == "none" ]]
    then
      qc_trim_SE "$read1" "$out_dir" $ram $threads
      mv "${read1/.f*/.trimmed.fq.gz}" "$out_dir"
      read1="${out_dir}/$(basename ${read1/.f*/.trimmed.fq.gz})"
      if [[ $T1 == "B" ]]
      then
          BOWTIE_aligner "${read1}" "$threads" "$genome1" "$out_dir" "$name" "$ram"
      elif [[ $T1 == "E" ]]
      then
          STAR_align "$threads" "$genome1" "${read1}" "$out_dir" "$name" "$ram" "$G1"
      fi
    else
        qc_trim_PE "$read1" "$read2" "$out_dir" $ram $threads
        mv "${1/f*/forward.fq.gz}" "${2/f*/reverse.fq.gz}" "$out_dir"
        read1="${out_dir}/$(basename ${read1/.f*/.trimmed.fq.gz})"
        read2="${out_dir}/$(basename ${read2/.f*/.trimmed.fq.gz})"
        #do PE aligne like above here
        if [[ $T1 == "B" ]]
        then
            BOWTIE_alignerPE "${1/f*/forward.fq.gz}" "$threads" "$genome1" "$out_dir" "$name" "$ram" "${2/f*/reverse.fq.gz}"
        elif [[ $T1 == "E" ]]
        then
            STAR_align "$threads" "$genome1" "${read1/.f*/.trimmed.fq.gz}" "$out_dir" "$name" "$ram" "$G1" "${1/f*/forward.fq.gz}" "${2/f*/reverse.fq.gz}"
        fi
    fi

bam_file="${out_dir}/${name}.$(printf $(basename $genome1) | cut -f 1 -d '.').bam"
#this takes the first 2500 reads and calculates the read length
read_length=$(zcat $read1 | head -n 10000 | awk 'NR%4 == 2 {lengths[length($0)]++} END {for (l in lengths) {print l}}')
do_calcs $out_dir $genome1 $bam_file $G1 $threads $T1 $read_length
if [[ $vc = "T" ]]; then
    VaraintCall "$genome1" "$bam_file" "${out_dir}/${name}" "${name}"
fi

    if [[ $genome2 != "none" ]]
    then
      #convert unaligned to fasta - STAR now has this built in :)
      mv "${out_dir}/${name}Unmapped.out.mate1.fastq.gz" "${out_dir}/${name}_${genome1}_Unmapped.out.mate1.fastq.gz"
      gen=$(basename $genome1)
      read1_unaligned="${out_dir}/${name}_${gen}_Unmapped.out.mate1.fastq.gz"
      #what if the first alignement was done with bowtie??
      if [[ $T2 == "B" ]]
      then
        BOWTIE_aligner "$read1_unaligned" "$threads" "$genome2" "$out_dir" "$name" "$ram"
      elif [[ $T2 == "E" ]]
      then
        STAR_align "$threads" "$genome2" "$read1_unaligned" "$out_dir" "$name" "$ram"
      fi
    else
      gen=$(basename $genome1)
      read1_unaligned="${out_dir}/${name}_${gen}_Unmapped.out.mate1.fastq.gz"
      read1_unaligned="${out_dir}/${name}_${gen}_Unmapped.out.mate2.fastq.gz"
      if [[ $T2 == "B" ]]
      then
          BOWTIE_aligner "$read1_unaligned" "$threads" "$genome2" "$out_dir" "$name" "$ram" "$read2_unaligned"
      elif [ $T2 == "E" ]
      then
          STAR_align "$threads" "$genome2" "$read1_unaligned" "$out_dir" "$name" "$ram" "$read2_unaligned"
      fi
      bam_file="${out_dir}/${name}.$(printf $(basename $genome2) | cut -f 1 -d '.').bam"
      do_calcs $out_dir $genome2 $bam_file $G2 $threads $T2 $read_length
      if [[ $vc = "T" ]]; then
          VaraintCall "$genome2" "$bam_file" "${out_dir}/${name}" "${name}"
      fi
    fi
#cleanup

#see what shoudl be removed, remember to leave those reads unaligned to genome two, may want to balst them or something

done<"$file_in"


