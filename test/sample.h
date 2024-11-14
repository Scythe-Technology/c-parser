struct Test {
    int a;
    int b;
};

struct Test2 {
    int a;
    int b, c;
};

typedef struct Test TEST;

int count();
int set_count(int c);
int large_fn(int c, int n, int o, int k);

int set_count(int c) {
    int bold = 0;
    return bold + c + 1;
}

typedef void (*callback)(int);
typedef void (*callback2)();
