#!/bin/bash

export OPENBLAS_NUM_THREADS=1

scheme=CollapsedSEM
form=SplitConservationForm

cd ../drivers

julia --project=.. --threads 4 advection_2d.jl -b 0.005 -m 0.2 -p 4 -r 4 -l 0.0 -M 16 -g 4 -s $scheme -f $form &
julia --project=.. --threads 4 advection_2d.jl -b 0.005 -m 0.2 -p 4 -r 4 -l 1.0 -M 16 -g 4 -s $scheme -f $form &
julia --project=.. --threads 16 advection_2d.jl -b 0.005 -m 0.2 -p 9 -r 9 -l 0.0 -M 16 -g 4 -s $scheme -f $form &
julia --project=.. --threads 16 advection_2d.jl -b 0.005 -m 0.2 -p 9 -r 9 -l 1.0 -M 16 -g 4 -s $scheme -f $form