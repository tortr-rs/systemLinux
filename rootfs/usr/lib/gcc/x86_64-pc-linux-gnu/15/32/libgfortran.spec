#
# This spec file is read by gfortran when linking.
# It is used to specify the libraries we need to link in, in the right
# order.
#

%rename lib liborig
*lib: --as-needed %{static-libquadmath:-Bstatic} -lquadmath %{static-libquadmath:-Bdynamic} --no-as-needed -lm %(liborig)
