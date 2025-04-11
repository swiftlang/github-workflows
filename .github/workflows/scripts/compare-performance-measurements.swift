//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

func printToStderr(_ value: String) {
  fputs(value, stderr)
}

extension Double {
  func round(toDecimalDigits decimalDigits: Int) -> Double {
    return (self * pow(10, Double(decimalDigits))).rounded() / pow(10, Double(decimalDigits))
  }
}

/// Given a performance measurement output, extract the actual measurement into a dictionary.
///
/// We expect every measurement to be on its own line with the name of the measurement on the left side of a colon and
/// the measurement on the right side of the colon.
///
/// For example, the output could be:
/// ```
/// Instructions executed for test case A: 123456789
/// Instructions executed for test case B: 2345678
/// Code Size: 34567
/// ```
func extractMeasurements(output: String) -> [String: Double] {
  var measurements: [String: Double] = [:]
  for line in output.split(separator: "\n") {
    guard let colonPosition = line.lastIndex(of: ":") else {
      printToStderr(
        "Ignoring following measurement line because it doesn't contain a colon: \(line)"
      )
      continue
    }
    let beforeColon = String(line[..<colonPosition]).trimmingCharacters(in: .whitespacesAndNewlines)
    let afterColon = String(line[line.index(after: colonPosition)...]).trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard let value = Double(afterColon) else {
      printToStderr(
        "Ignoring following measurement line because the value can't be parsed as a Double: \(line)"
      )
      continue
    }
    measurements[beforeColon] = value
  }
  return measurements
}

func run(
  baselinePerformanceOutput: String,
  changedPerformanceOutput: String,
  sensitivityPercentage: Double
) -> (output: String, hasDetectedSignificantChange: Bool) {
  let baselineMeasurements = extractMeasurements(output: baselinePerformanceOutput)
  let changedMeasurements = extractMeasurements(output: changedPerformanceOutput)

  var hasDetectedSignificantChange = false
  var output = ""
  for (measurementName, baselineValue) in baselineMeasurements.sorted(by: { $0.key < $1.key }) {
    guard let changedValue = changedMeasurements[measurementName] else {
      output += "🛑 \(measurementName) not present after changes\n"
      continue
    }
    let differencePercentage = (changedValue - baselineValue) / baselineValue * 100
    let rawMeasurementsText = "(baseline: \(baselineValue), after changes: \(changedValue))"
    if differencePercentage < -sensitivityPercentage {
      output +=
        "🎉 \(measurementName) improved by \(-differencePercentage.round(toDecimalDigits: 3))% \(rawMeasurementsText)\n"
      hasDetectedSignificantChange = true
    } else if differencePercentage > sensitivityPercentage {
      output +=
        "⚠️ \(measurementName) regressed by \(differencePercentage.round(toDecimalDigits: 3))% \(rawMeasurementsText)\n"
      hasDetectedSignificantChange = true
    } else {
      output +=
        "➡️ \(measurementName) did not change significantly with \(differencePercentage.round(toDecimalDigits: 3))% \(rawMeasurementsText)\n"
    }
  }
  return (output, hasDetectedSignificantChange)
}

guard CommandLine.arguments.count > 3 else {
  printToStderr(
    """
    Usage: compare-performance-measurements.swift <BASELINE> <WITH_CHANGES> <SENSITIVITY>

    Where BASELINE and WITH_CHANGES are strings containing the performance measurements, with each measurement on a
    separate line with the name of the measurement on the left side of a colon and the measurement on the right side of
    the colon.

    For example, the baseline could be.
    ```
    Instructions executed for test case A: 123456789
    Instructions executed for test case B: 2345678
    Code Size: 34567
    ```

    Sensitivity is the percentage after which a change should be considered meaningful. Eg. specify 0.5 to report a
    significant performance change if any of the measurements changed by more than 0.5% (either improved or regressed).
    """
  )
  exit(1)
}

let baselinePerformanceOutput = CommandLine.arguments[1]
let changedPerformanceOutput = CommandLine.arguments[2]
let sensitivityPercentage = Double(CommandLine.arguments[3])

guard let sensitivityPercentage else {
  printToStderr("Sensitivity was not a valid Double value")
  exit(1)
}

let (output, hasDetectedSignificantChange) = run(
  baselinePerformanceOutput: baselinePerformanceOutput,
  changedPerformanceOutput: changedPerformanceOutput,
  sensitivityPercentage: sensitivityPercentage
)

print(output)
if hasDetectedSignificantChange {
  exit(1)
}
