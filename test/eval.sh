input="$1"

./d2qbe "$input" | ./qbe/qbe > tmp.s
cc -o tmp tmp.s ext.o
./tmp
echo $?
