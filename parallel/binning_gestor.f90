module binning_gestor
    implicit none
        contains
        subroutine binning(data_arr, num, output_file)
        ! data_arr: array containing the data to bin
        ! num: size of data_arr
        ! file_name: name of the output file
             implicit none 
             character(len=*), intent(in) :: output_file
             integer, intent(in) :: num ! number of elements in data_arr
             double precision, dimension(:), intent(in) :: data_arr
             integer(8) :: ii,i, mm, max_m, block_length, block_num
             double precision :: mean, sigma, variance, mean_median, std_median
             double precision, dimension(:), allocatable :: means_arr, mean_results, std_results, my_data
             double precision, dimension(:,:), allocatable :: binning_mat
             integer, dimension(:), allocatable :: pos_to_transfer, displs
             integer :: file_status, ierror, comm, rank, nprocs, n_blocks_remaining, blocks_per_proc, end_block, start_block
             integer, parameter :: MASTER = 0
             include 'mpif.h'
             double precision :: med_mean, med_std
             integer :: status(MPI_STATUS_SIZE)

             ! MPI initialization
             call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierror)
             call MPI_COMM_SIZE(MPI_COMM_WORLD, nprocs, ierror)

             ! Calculate max binning length
             allocate(pos_to_transfer(nprocs))
             allocate(displs(nprocs))
             
            ! Calculate max binning length
             max_m = int(log(dble(num)) / log(2.0d0)) ! Max block length exponent
             allocate(binning_mat(max_m+1, 2))
             allocate(mean_results(max_m+1))
             allocate(std_results(max_m+1))
             
            ! Distribute blocks between processors
            ! Each proc is goning to do the binning of X number of blocks with same length
             n_blocks_remaining = mod(max_m+1, nprocs)

             if (rank < n_blocks_remaining) then
                 blocks_per_proc = (max_m+1) / nprocs + 1
                 start_block = rank * blocks_per_proc
                 end_block = start_block + blocks_per_proc - 1 
             else
                 blocks_per_proc = (max_m+1) / nprocs
                 start_block = n_blocks_remaining * (blocks_per_proc + 1) + (rank - n_blocks_remaining) * blocks_per_proc
                 end_block = start_block + blocks_per_proc - 1
             end if

            ! pos to tranfer contains number of blocks for proc (ex. pos_to_transfer = [2,2,1,1])
            ! Generate an array with all the number of positions that will be sent later
            call MPI_ALLGATHER(blocks_per_proc,1,MPI_INT,pos_to_transfer,1,MPI_INT,MPI_COMM_WORLD, ierror)

            print *, rank, pos_to_transfer
            ! displs counts space in pos_to_transfer array to avoid overlapping (ex. displs = [0,2,4,5]) 
            displs(1) = 0
            do i = 2, nprocs
                displs(i) = displs(i-1)+pos_to_transfer(i-1)
            end do

            ! Start doing binning
             do mm = start_block, end_block ! Iterate over block length
                block_length = 2**mm
                block_num = 0
                allocate(means_arr(ceiling(num/dble(block_length))))
                
                ! For each block length
                ! Store mean of each sub block
                do ii = 1, num, block_length
                    block_num = block_num + 1
                    if ((ii+block_length-1).gt.num) then
                        means_arr(block_num) = sum(data_arr(ii:num))/size(data_arr(ii:num))
                    else
                        means_arr(block_num) = sum(data_arr(ii:ii+block_length-1))/dble(block_length)
                    end if
                end do
                ! Calculate mean of means
                mean = sum(means_arr)/dble(block_num)
   
                ! Calculate standard deviation and correct it
                variance = 0.
                do ii = 1, block_num
                    variance = variance + (means_arr(ii)-mean)**2
                end do
                sigma = sqrt(variance)/sqrt(dble(block_num)*dble(block_num-1))
   
                ! Store in binning_mat
                binning_mat(mm+1,1) = mean
                binning_mat(mm+1,2) = sigma
                deallocate(means_arr)
           end do

           ! Share results to master
           call MPI_Gatherv(binning_mat(start_block+1:end_block+1,1), pos_to_transfer(rank+1), MPI_DOUBLE_PRECISION, mean_results, pos_to_transfer,displs, MPI_DOUBLE_PRECISION, &
           MASTER, MPI_COMM_WORLD, ierror)

           call MPI_Gatherv(binning_mat(start_block+1:end_block+1,2), pos_to_transfer(rank+1), MPI_DOUBLE_PRECISION, std_results, pos_to_transfer,displs, MPI_DOUBLE_PRECISION, &
           MASTER, MPI_COMM_WORLD, ierror)
        
        ! Calculate median of mean and std
        mean_median = calculate_median(mean_results, max_m+1)
        std_median = calculate_median(std_results, max_m+1)

        ! Write file with results
        if (rank == MASTER) then
             open(2, file=output_file, status='replace', action='write', iostat=file_status)
                 if (file_status /= 0) then
                      print*, "Error opening file for writing"
                      stop
                 endif
                 write(2,*) "The mean value is:",mean_median , "and standard  deviation is:",std_median
             close(2)
        endif
    return
    end 

    real function calculate_median(arr, n)
        integer(8), intent(in) :: n
        double precision, dimension(:), intent(in) :: arr
        real(kind=kind(0.0d0)) :: median
        integer :: mid_index
        
        mid_index = n / 2
        
        if (mod(n, 2) == 0) then
            median = real(arr(mid_index) + arr(mid_index + 1), kind=kind(0.0d0)) / 2.0
        else
            median = real(arr(mid_index + 1), kind=kind(0.0d0))
        end if
        
        calculate_median = median
        
    return    
    end 

end module binning_gestor
