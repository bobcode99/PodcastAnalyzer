//
//  CrashReportingService.swift
//  PodcastAnalyzer
//
//  Lightweight MetricKit subscriber for crash diagnostics and performance metrics
//

import Foundation
import MetricKit
import os.log

final class CrashReportingService: NSObject {
  static let shared = CrashReportingService()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "CrashReporting")

  private override init() {
    super.init()
  }

  /// Register as MetricKit subscriber. Call once during app launch.
  func start() {
    MXMetricManager.shared.add(self)
    logger.info("CrashReportingService registered as MetricKit subscriber")
  }
}

// MARK: - MXMetricManagerSubscriber

extension CrashReportingService: MXMetricManagerSubscriber {
  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      logger.info("Received MetricKit metric payload: \(payload.dictionaryRepresentation())")
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      if let crashDiagnostics = payload.crashDiagnostics, !crashDiagnostics.isEmpty {
        logger.error("MetricKit crash diagnostics received: \(crashDiagnostics.count) crash(es)")
      }
      if let hangDiagnostics = payload.hangDiagnostics, !hangDiagnostics.isEmpty {
        logger.warning("MetricKit hang diagnostics received: \(hangDiagnostics.count) hang(s)")
      }
      if let cpuExceptionDiagnostics = payload.cpuExceptionDiagnostics, !cpuExceptionDiagnostics.isEmpty {
        logger.warning("MetricKit CPU exception diagnostics: \(cpuExceptionDiagnostics.count)")
      }
      if let diskWriteExceptionDiagnostics = payload.diskWriteExceptionDiagnostics, !diskWriteExceptionDiagnostics.isEmpty {
        logger.warning("MetricKit disk write exception diagnostics: \(diskWriteExceptionDiagnostics.count)")
      }
      logger.info("Full diagnostic payload: \(payload.dictionaryRepresentation())")
    }
  }
}
