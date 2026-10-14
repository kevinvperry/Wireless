import Foundation
@main struct VerifyRegions {
 static func main() throws {
  guard CommandLine.arguments.count == 3 else {
   fatalError("Usage: validate-regions <catalogue-stations.json> <capital-cities.json>")
  }
  struct Reference: Decodable { let city: String; let station_group: String? }
  let reference = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
  let stations = try JSONDecoder().decode([DirectoryStation].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
  precondition(DiscoverRegion.allCases.map(\.rawValue) == ["National", "Melbourne", "Sydney", "Brisbane", "Adelaide", "Perth", "Hobart", "Canberra", "Darwin", "Other"])
  for region in DiscoverRegion.allCases {
   let result = DiscoverRegions.stations(stations, in: region)
   let ids = reference.filter { $0.city == region.rawValue }.compactMap { $0.station_group.map { "station_" + $0 } }
   if !ids.isEmpty {
    precondition(Array(result.prefix(ids.count)).map(\.id) == ids, "Wrong flagship order: \(region)")
   }
   print("\(region.rawValue): \(result.count) stations; first: \(result.first?.name ?? "none")")
  }
  precondition(stations.allSatisfy { !DiscoverRegions.regions(for: $0).isEmpty })
  precondition(DiscoverRegions.stations(stations, in: .national).contains { $0.name == "ABC Classic" })
  precondition(!DiscoverRegions.stations(stations, in: .national).contains { $0.name == "ABC Ballarat" })
  precondition(DiscoverRegions.stations(stations, in: .other).contains { $0.name == "ABC Ballarat" })
  print("All 53 curated flagships ordered correctly; every station remains reachable.")
 }
}
