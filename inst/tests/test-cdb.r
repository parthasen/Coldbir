require(Coldbir)
path <- tempfile()
size <- 1e3
db <- cdb(path, log_level = 1, read_only = F)

context("INITIALIZE DATABASE")
##############################
test_that("init cdb", {
  expect_equal(path, db$path)
})

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

x <- as.factor(c(NA, NA))
db["x"] <- x
test_that("factor with only na", {
  expect_equal(x, db["x"])
})

# Test if escape characters works
x <- c("a\n", "\tc\v\n", "d\a\vx\ry\f\tz")
db["x"] <- x
test_that("escape_char", {
  expect_equal(escape_char(x), as.character(db["x"]))
})

x <- .POSIXct(runif(size) * unclass(Sys.time()))
db["x"] <- x
test_that("POSIXct", {
  expect_equal(as.character(x), as.character(db["x"]))
})

test_that("non-existing", {
  expect_error(db["non-existing"])
})

context("VARIABLE DOCUMENTATION")
#################################
x <- list(a = "text", b = list(c = 1:3, d = 4), c = "åäö")
db["x"] <- doc(x)
test_that("get documentation", {
  expect_equal(list(x), db$get_doc("x"))
})

context("VARIABLE DIMENSIONS")
##############################
x <- sample(1:5, size, replace = T)
dims <- c(2012, "test")
db["x", dims] <- x
test_that("put/get variable with dimensions", {
  expect_error(db["non-existing", dims])
  expect_equal(x, db["x", dims])
  expect_true(file.exists(file.path(db$path, "x", "data", "d[2012][test].cdb.gz")))
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

context("REPLACE NA")
#####################
x <- c(T, F, NA, F, T)
db["x"] <- x
test_that("logical replaces NA", {
  expect_equal(sum(x, na.rm = T), sum(db["x", na = F]))
})

x <- c(1, NA, 3)
db["x"] <- x
test_that("integer replaces NA", {
  expect_equal(1:3, db["x", na = 2])
})

x <- c("a", NA)
db["x"] <- x
test_that("character replaces NA", {
  expect_equal(as.factor(c("a", "b")), db["x", na = "b"])
})

context("DATASETS")
###################
x <- data.table(MASS::survey)

# In addition we change the column names
# to specifically test issue 49.
setnames(x, c("Wr.Hnd", "NW.Hnd", "Pulse"), c("var", "x", "z"))

db[, "survey"] <- x

# Order columns by name since the folders in the database
setcolorder(x, sort(names(x)))

test_that("get dataset", {
  expect_equal(x, db[, "survey"])
})

context("READ ONLY")
####################
db$read_only <- T
test_that("put variable", {
  expect_error({ db["x"] <- 1:10})
})
test_that("put docs", {
  expect_error({ db["x"] <- doc(a = 1, b = 2) })
})
db$read_only <- F

context("LOOKUP TABLES")
########################
a <- c("b", "c"); db["x", "a"] <- a
b <- c("a", "b", NA); db["x", "b"] <- b
c <- c("d", "c", NA, "c"); db["x", "c"] <- c
d <- "c"; db["x", "d"] <- d
e <- NA; db["x", "e"] <- e
test_that("Different lookup tables between dimensions", {
  expect_equal(a, as.character(db["x", "a"]))
  expect_equal(b, as.character(db["x", "b"]))
  expect_equal(c, as.character(db["x", "c"]))
  expect_equal(d, as.character(db["x", "d"]))
  expect_equal(e, as.character(db["x", "e"]))
})

# CLEAN UP
unlink(path, recursive = T)
