# Find the chunk files of a chunked bootstrap run

Returned in a deterministic order, and named so a single full run
(`bagging.rds`) and a chunked run never collide.

## Usage

``` r
boot_chunk_files(out_dir, prefix = "bagging")
```

## Arguments

- out_dir:

  Directory to look in.

- prefix:

  File-name prefix the runner used.

## Value

A sorted character vector of full paths, possibly empty.

## See also

[`boot_pool_chunks()`](https://ehrlinger.github.io/hvtiRbootstrap/reference/boot_pool_chunks.md)
