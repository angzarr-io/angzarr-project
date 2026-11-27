Feature: Wire versioning - a package per break, a stamp per store
  Every wire break is a new proto package; each old package is kept frozen
  and compiled in (14.113, docs/design/wire-versioning.md). A store records
  the package version that wrote each row and the newest it has seen: a
  reader decodes a row as the package it names and maps it to the current
  shape; every write is current. A store written before the stamp existed
  is told by the shape of its rows, once. A store of a version this build
  does not know is refused, untouched.

  Background:
    Given a store the build opens

  @wire-versioning
  @C-0883
  Scenario: A new store is stamped with the build's package
    When the store is opened
    Then the store's stamp is oldest "io.angzarr.v1" and newest "io.angzarr.v1"

  @wire-versioning
  @C-0884
  Scenario: A stamped store's version reads back without migrating it
    Given the store was written by "io.angzarr.v1"
    When the stamp is read at its path before any open
    Then the stamp is oldest "io.angzarr.v1" and newest "io.angzarr.v1"
    And the store is as it was

  @wire-versioning
  @C-0885
  Scenario: An unstamped legacy store is detected by the shape of its rows
    Given an unstamped store whose pages and snapshot are in the "io.angzarr.v0" shape
    When the store is opened
    Then the store's stamp is oldest "io.angzarr.v0" and newest "io.angzarr.v0"
    And every row is marked "io.angzarr.v0"
    And a backup of the store as it was exists beside it

  @wire-versioning
  @C-0886
  Scenario: A legacy store reads in the current shape
    Given an unstamped store whose pages and snapshot are in the "io.angzarr.v0" shape
    When the store is opened
    Then each page reads as a current page with the same sequence, event, cause, correlation, recorded time and rules version
    And a page produced by a fact reads with a fact cause carrying the fact's origin
    And the snapshot reads as a current snapshot with the same sequence, state and rules version

  @wire-versioning
  @C-0887
  Scenario: A legacy store written to holds both versions and writes the current one
    Given an unstamped store whose pages and snapshot are in the "io.angzarr.v0" shape
    When the store is opened and an event is appended
    Then the appended row is marked "io.angzarr.v1"
    And the store's stamp is oldest "io.angzarr.v0" and newest "io.angzarr.v1"
    And the legacy rows are byte for byte as they were

  @wire-versioning
  @C-0888
  Scenario: Detection runs once
    Given an unstamped store whose pages and snapshot are in the "io.angzarr.v0" shape
    And the store was opened once
    When the store is opened again
    Then no row is classified again

  @wire-versioning
  @C-0889
  Scenario Outline: A store that fits no known shape is refused, untouched
    Given an unstamped store with <fault>
    When the store is opened
    Then the open is refused "angzarr-ports-store-wire-unrecognised"
    And the store is as it was, with no stamp

    Examples:
      | fault                                                         |
      | a page that is neither the v0 nor the v1 shape                |
      | a page whose sequence is not its row's sequence               |
      | a v0 page after a v1 page in one stream                       |

  @wire-versioning
  @C-0890
  Scenario: A store of a newer wire version is refused, untouched
    Given the store was written by a build whose newest package is "io.angzarr.v2"
    When the store is opened by a build whose newest package is "io.angzarr.v1"
    Then the open is refused "angzarr-ports-store-wire-newer-than-build"
    And the store is as it was

  @wire-versioning
  @C-0891
  Scenario: A legacy store with pending transient rows is refused until they are cleared
    Given an unstamped store in the "io.angzarr.v0" shape with 2 outbox entries and 1 dead letter
    When the store is opened
    Then the open is refused "angzarr-ports-store-wire-legacy-transient"
    And the refusal counts 2 outbox entries and 1 dead letter

  @wire-versioning
  @C-0892
  Scenario: A frozen package changed is refused by the gate
    Given "io.angzarr.v0" is frozen
    When a branch changes a file of "io.angzarr.v0" in any way
    Then the proto frozen gate fails, naming the file

  @wire-versioning
  @C-0893
  Scenario: A breaking change in a non-frozen package is refused by the gate
    Given "io.angzarr.v1" is not frozen
    When a branch renumbers a field of "io.angzarr.v1" in place
    Then the proto breaking gate fails against the baseline, with no exception
    And a branch that instead creates "io.angzarr.v2" and freezes "io.angzarr.v1" passes
