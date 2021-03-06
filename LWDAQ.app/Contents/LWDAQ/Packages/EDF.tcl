# LWDAQ EDF Package, (c) 2015 Kevan Hashemi, Open Source Instruments Inc.
#
# A library of routines to create and add to EDF (European Data Format)
# files for neuroscience research, in which we assume that all signals
# are are derived from SCTs (subcutaneous transmitters) that produce 
# sixteen-bit unsigned data samples, which we must translate into the EDF 
# sixteen-bit little-endian signed integers, and for which all signals have 
# the same voltage range and units.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

# Load this package or routines into LWDAQ with "package require EDF".
package provide EDF 1.1

# Global variables that we can change to re-configure the EDF routines.
set EDF(physical_unit) "uV"
set EDF(physical_min) "-18000"
set EDF(physical_max) "+9000"
set EDF(filtering) "DC-Blocking High-Pass @ <1Hz, Anti-Aliasing Low-Pass @ 1/3 Sample Rate in Hz." 
set EDF(transducer) "Metal electrodes to 10-MOhm input impedance"

# We declare a global EDF array containing constants derived from the EDF
# header format definition, see http://www.edfplus.info/specs/edf.html. 
# We declare only the constants that are likely to be needed by multiple
# routines, but not those that will be used only once, in the header
# creation routine. The constants should not be changed by other routines.
set EDF(patient_len) 80
set EDF(patient_loc) 8
set EDF(recording_len) 80
set EDF(num_records_len) 8
set EDF(num_records_loc) 236
set EDF(header_size_loc) 184
set EDF(header_size_len) 8

#
# EDF_string_fix arranges strings for the EDF header. In the EDF header, strings
# must be a particular length, left-adjusted, and padded with spaces. We declare 
# a routine to perform this padding and curtailing, in case the string we want 
# to include is too long for the space available.
#
proc EDF_string_fix {s l} {
	set s [string range $s 0 [expr $l - 1]]
	while {[string length $s] < $l} {append s " "}
	return $s
}

#
# EDF_create creates a new European Data Format file, which is
# a format accepted by many EEG and ECG display programs. The file includes
# no data, only the header, which is text-only. For a description of the EDF
# file format, see http://www.edfplus.info/specs/edf.html. The format breaks
# a recording into intervals, which they call "records", each of which is of
# a fixed duration in seconds. Each record has a fixed number of signals, and
# each signal contains a fixed number of samples. All samples are little-endian
# two-byte signed integers. The minimum value is -32768 and the maxium is 
# 32767. We cannot store values that range from 0-65536, nor can we store
# real-valued samples. But this routine does not store signals, it creates the
# header file, in which the number of records is set to zero, in anticipation
# of later routines adding records to the file and, in doing so, incrementing
# the number of data records field in the header. The total length of the header
# will be 256 bytes plus another 256 bytes per signal. If a file already
# exists with the specified name, this routine will delete and replace the
# previous file. The routine requires taht we tell it the file name, the interval
# length in seconds, and we provide a list of signal labels with their number
# of samples per second. For example, "1 512 2 512 4 256 8 1024". Note that the 
# EDF header will specify the number of samples per interval, which we calculate 
# from the sample rate and interval length. If we don't specify a date, we use 
# the current date. The patient and recording strings are optional, and will be 
# empty if we don't specifify them.
#
proc EDF_create {file_name interval signals {date ""} {patient ""} {recording ""}} {
	global EDF
	
	# If we don't specify the date, use the current date.
	if {$date == ""} {set date [clock seconds]}
	
	# Start with an empty header string.
	set header ""

	# Fill in version, patient, and recording fields.
	append header [EDF_string_fix "0" 8]
	append header [EDF_string_fix $patient $EDF(patient_len)]
	append header [EDF_string_fix $recording $EDF(recording_len)]

	# Get the start date and time from the name of the NDF file.
	append header [EDF_string_fix [clock format $date -format %d\.%m\.%y%H\.%M\.%S] 16]

	# Header length will go here, we'll fill it in when we know it.
	append header {HHHHHHHH}

	# A reserved field.
	append header [EDF_string_fix "" 44]

	# The number of data records. Zero now, but will be updated every new interval.
	append header [EDF_string_fix "0" $EDF(num_records_len)]

	# Duration of one data record in seconds.
	append header [EDF_string_fix $interval 8]

	# The number of signals in each data record. We have a signal list that 
	# provides a label and samples per second for each signal
	append header [EDF_string_fix [expr [llength $signals] / 2] 4]

	# A identifying label for each signal.
	foreach {id fq} $signals {
		append header [EDF_string_fix "$id" 16]
	}
	
	# A transducer type for each signal.
	foreach {id fq} $signals {
		append header [EDF_string_fix $EDF(transducer) 80]
	}
	
	# Physical units, minimum value in those units and maximum value for each
	# signal. We use the nominal values for a transmitter with 2.7-V battery 
	# and x100 gain.
	foreach {id fq} $signals {
		append header [EDF_string_fix $EDF(physical_unit) 8]
	}
	foreach {id fq} $signals {
		append header [EDF_string_fix $EDF(physical_min) 8]
	}
	foreach {id fq} $signals {
		append header [EDF_string_fix $EDF(physical_max) 8]
	}
	
	# The minimum and maximum digital values of the samples for each signal.
	foreach {id fq} $signals {
		append header [EDF_string_fix "-32768" 8]
	}
	foreach {id fq} $signals {
		append header [EDF_string_fix "+32767" 8]
	}
	
	# The type of filtering applied before sampling for each signal. We 
	# assume a 0.3-160 Hz device.
	foreach {id fq} $signals {
		append header [EDF_string_fix $EDF(filtering) 80]
	}
	
	# The number of samples per record. This is the sample frequency multiplied by the
	# playback interval.
	foreach {id fq} $signals {
		append header [EDF_string_fix "[expr round($interval * $fq)]" 8]
	}
	
	# A reserved field.
	foreach {id fq} $signals {
		append header [EDF_string_fix "" 32]
	}
	
	# Now we have the header, we can write its length into the header length field.
	set header_len [string length $header]
	set header [regsub {HHHHHHHH} $header [EDF_string_fix $header_len 8]]

	# Make sure we have only printable characters in the header. We replace any non-printable
	# characters with a space.
	set header [regsub -all {[^ -~]} $header " "]
	
	# Open the file for writing, and print the header to the file, making sure we don't 
	# leave a newline character at the end.
	set f [open $file_name w]
	puts -nonewline $f $header
	close $f

	# Return the length of the header.
	return $header_len
}

#
# EDF_num_records_incr increments the number of data records field in the header of the
# named EDF file.
#
proc EDF_num_records_incr {file_name} {
	global EDF

	# Find the number of records counter in the header.
	set f [open $file_name r+]
	fconfigure $f -translation binary
	seek $f $EDF(num_records_loc)
	set num_records [read $f $EDF(num_records_len)]
	
	# Increment number of records and write it back into the header.
	incr num_records
	seek $f $EDF(num_records_loc)
	puts -nonewline $f [EDF_string_fix $num_records $EDF(num_records_len)]
	close $f

	# Return the new value of the number of recrods.
	return $num_records
}

#
# EDF_num_records_write sets the number of records field in the header of
# and EDF file.
#
proc EDF_num_records_write {file_name num_records} {
	global EDF

	# Find the number of records counter in the header.
	set f [open $file_name r+]
	fconfigure $f -translation binary
	seek $f $EDF(num_records_loc)
	puts -nonewline $f [EDF_string_fix $num_records $EDF(num_records_len)]
	close $f

	# Return the new value of the number of recrods.
	return $num_records
}

#
# EDF_num_records_read gets the number of records field from the header of
# and EDF file.
#
proc EDF_num_records_read {file_name} {
	global EDF

	# Find the number of records counter in the header.
	set f [open $file_name r+]
	fconfigure $f -translation binary
	seek $f $EDF(num_records_loc)
	set num_records [read $f $EDF(num_records_len)]
	close $f
	
	# Return the new value of the number of records.
	return $num_records
}

#
# EDF_patient_read gets the patient name field from the header of
# and EDF file.
#
proc EDF_patient_read {file_name} {
	global EDF

	# Find the patient field in the header.
	set f [open $file_name r+]
	fconfigure $f -translation binary
	seek $f $EDF(patient_loc)
	set patient [read $f $EDF(patient_len)]
	close $f
	
	# Return the new patient name, with white spaces removed
	return [string trim $patient]
}

#
# EDF_header_size returns the length of an EDF file's header field.
#
proc EDF_header_size {file_name} {
	global EDF
	
	# Check that the file exists.
	if {![file exists $file_name]} {
		error "Cannot find $file_name\."
	}

	# Find the header size value in the header.
	set f [open $file_name r+]
	fconfigure $f -translation binary
	seek $f $EDF(header_size_loc)
	set header_size [read $f $EDF(header_size_len)]
	close $f
	
	# Check for errors.
	if {![string is integer -strict $header_size]} {
		error "Invalid EDF header size field."
	}
	
	# Return the value.
	return $header_size
}

#
# EDF_append adds data to an existing EDF file. It takes a string of unsigned integers in the 
# range 0..65535 and translates them into little-endian sixteen-bit signed integers, with 0 
# being translated to -32768 and 65535 becoming 32767. The binary data is added to the end of
# the named EDF file. If the incoming data is outside the range 0..65535, it will be translated
# as if it were its value modulo 65536.
#
proc EDF_append {file_name data} {

	# Check that the file exists.
	if {![file exists $file_name]} {
		error "Cannot find $file_name\."
	}
	
	# Translate ascii string to binary data.
	set binary_data ""
	foreach x $data {
		append binary_data [binary format s [expr round($x) - 32768]]
	}
	
	# Append binary data to file.
	set f [open $file_name a]
	fconfigure $f -translation binary
	puts -nonewline $f $binary_data
	close $f
	
	# Return number of samples written.
	return [llength $data]
}

#
# EDF_merge takes one or more EDF files and copies their contents into a new EDF file. The
# routine checks that the headers of all input files are the same length, but otherwise does 
# not confirm that the files have identical data formats. The header of the output file is
# the same as the header of the input file. If the outfile name is the same as the first
# infile name, the routine simply adds the remaining input file contents to the existing
# outfile.
#
proc EDF_merge {outfile_name infile_name_list} {

	# Check that the input files exist.
	if {[llength $infile_name_list] == 0} {
		error "No input files specified."
	}
	foreach fn $infile_name_list {
		if {![file exists $fn]} {
			error "Cannot find input file $fn\."
		}
	}
	
	# Copy the first input file to the output file.
	set if1 [lindex $infile_name_list 0]
	if {[file normalize $outfile_name] != [file normalize $if1]} {
		if {[file exists $outfile_name]} {
			file delete $outfile_name
		}
		file copy $if1 $outfile_name
	}
	set infile_name_list [lrange $infile_name_list 1 end]
	
	# Determine the header size and number of records in the output file.
	set hso [EDF_header_size $outfile_name]
	set nro [EDF_num_records_read $outfile_name]
	
	# Transfer data from each subsequent input file.
	foreach fn $infile_name_list {
		# Determine the header size and number of records in the input file.
		set hsi [EDF_header_size $fn]
		set nri [EDF_num_records_read $fn]
		if {$hsi != $hso} {
			error "Header mismatch [file tail $outfile_name] and [file tail $fn]."
		}
	
		# Read the data records out of the input file.
		set f [open $fn r]
		fconfigure $f -translation binary
		seek $f $hsi
		set dri [read $f]
		close $f
	
		# Append the data records to the output file.
		set f [open $outfile_name a]
		fconfigure $f -translation binary
		puts -nonewline $f $dri
		close $f
	
		# Keep track of the number of records in the file.
		set nro [expr $nro + $nri]
		EDF_num_records_write $outfile_name $nro
	}
	
	# Return the number of data records in the output file.
	return $nro
}