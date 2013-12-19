path <- tempfile()
size <- 1e3
db <- cdb(path, log_level = 1, read_only = F)

context("INITIALIZE DATABASE")
##############################
test_that("init cdb", {
  expect_equal(path, db$path)
})

db$clean()

context("DATABASE CONFIG")
##########################
db$put_config()
rds <- file.path(db$path, Coldbir:::.config_filename)
test_that("create config file in an empty database", {
  expect_true(file.exists(rds))
  expect_identical(readRDS(rds), list(
    read_only = F,
    db_version = NA_real_,
    n_row = NA_integer_
  ))
})

db$clean()

context("GUESSING NROW")
########################
test_that("nrow when database is empty", {
  expect_true(is.na(db$guess_db_nrow()))
})

x <- sample(1:5, size, replace = T)
db["x"] <- x
test_that("nrow when database contains one variable without any dimentions", {
  expect_equal(db$guess_db_nrow(), size)
})

db$clean()

context("VARIABLE TYPES")
#########################
x <- sample(c(T, F), size, replace = T)
db["x"] <- x
test_that("logical", {
  expect_equal(x, db["x"])
})

x <- sample(c(T, F, NA), size, replace = T)
db["x"] <- x
test_that("logical na", {
  expect_equal(x, db["x"])
})

x <- sample(c(0, 1, 10000, .Machine$integer.max, NA), size, replace = T)
db["x"] <- x
test_that("integer", {
  expect_equal(x, db["x"])
})

x <- sample(c(-100, -50, 0, 50, 100, NA), size, replace = T)
db["x"] <- x
test_that("double", {
  expect_equal(x, db["x"])
})

x <- sample(LETTERS, size, replace = T)
db["x"] <- x
test_that("character", {
  expect_equal(as.factor(x), db["x"])
})

x <- .POSIXct(runif(size) * unclass(Sys.time()))
db["x"] <- x
test_that("POSIXct", {
  expect_equal(as.character(x), as.character(db["x"]))
})

# Test if escape characters works
x <- sample(c("a\n", "\tc\v\n", "d\a\vx\ry\f\tz"), size, replace = T)
db["x"] <- x
test_that("escape_char", {
  expect_equal(escape_char(x), as.character(db["x"]))
})

test_that("non-existing", {
  expect_error(db["non-existing"])
})

db$clean()

context("VARIABLE DOCUMENTATION")
#################################
db["x"] <- doc(a = 1, b = "c")
test_that("add docs as parameters", {
  expect_equal(list(a = 1, b = "c"), db$get_doc("x"))
})

x <- list(a = "text", b = list(c = 1:3, d = 4), c = "åäö")
db["x"] <- doc(x)
test_that("add docs as a list", {
    expect_equal(x, db$get_doc("x"))
})

x <- list(b = 1, c = 2)
db["x"] <- doc(a = x)  # special case
test_that("add docs as one parameter that includes a list", {
  expect_equal(list(a = x), db$get_doc("x"))
})

db$clean()

context("VARIABLE DIMENSIONS")
##############################
x <- sample(1:5, size, replace = T)
dims <- c(2012, "a")
db["x", dims] <- x
test_that("put/get variable with dimensions", {
  expect_error(db["non-existing", dims])
  expect_equal(x, db["x", dims])
  expect_true(file.exists(file.path(db$path, "x", "data", "d[2012][a].cdb.gz")))
})

x <- sample(1:5, size, replace = T)
dims <- NULL
db["x", dims] <- x

test_that("put/get variable with dims = NULL", {
  expect_equal(x, db["x", dims])
  expect_true(file.exists(file.path(db$path, "x", "data", "d.cdb.gz")))
})

test_that("non-existing dimensions", {
  expect_error(db["non-existing", dims])
})

db$clean()

context("REPLACE NA")
#####################
x <- c(T, F, NA, F, T)
db["x"] <- x
test_that("logical replaces NA", {
  expect_equal(sum(x, na.rm = T), sum(db["x", na = F]))
})

db$clean()

x <- c(1, NA, 3)
db["x"] <- x
test_that("integer replaces NA", {
  expect_equal(1:3, db["x", na = 2])
})

db$clean()

x <- c("a", NA)
db["x"] <- x
test_that("character replaces NA", {
  expect_equal(as.factor(c("a", "b")), db["x", na = "b"])
})

db$clean()

context("DATASETS")
###################
x <- data.table(MASS::survey)

# In addition we change the column names
# to specifically test issue 49.
setnames(x, c("Wr.Hnd", "NW.Hnd", "Pulse"), c("var", "x", "z"))

db[, c("survey")] <- x

setcolorder(x, sort(names(x)))

test_that("get dataset", {
  expect_equal(x, db[, "survey"])
})

db$clean()

context("READ ONLY")
####################
db$read_only <- T

test_that("put variable", {
  expect_error({ db["x"] <- 1:10})
})

test_that("put docs", {
  expect_error({ db["x"] <- doc(a = 1, b = 2) })
})

test_that("put config", {
  expect_warning(db$put_config())
})

test_that("clean", {
  expect_error(db$clean())
})

db$read_only <- F
db$clean()