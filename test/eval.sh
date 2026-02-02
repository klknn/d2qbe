input="$1"

./d2qbe "$input" | ./qbe/qbe > tmp.s
cc -o tmp tmp.s
./tmp
echo $?
