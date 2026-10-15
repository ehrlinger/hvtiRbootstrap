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

## Examples

``` r
out_dir <- file.path(tempdir(), "boot-chunk-files-example")
dir.create(out_dir)
invisible(file.create(file.path(out_dir, c(
  "bagging.chunk2.rds", "bagging.chunk1.rds", "bagging.rds", "notes.txt"
))))
basename(boot_chunk_files(out_dir))
#> [1] "bagging.chunk1.rds" "bagging.chunk2.rds"
unlink(out_dir, recursive = TRUE)
```
