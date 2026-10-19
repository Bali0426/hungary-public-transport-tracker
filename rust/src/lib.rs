pub mod api;
pub mod gtfs_rt;
pub mod static_db;

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use prost::Message;

    use crate::gtfs_rt::bkk::decode_bkk_vehicle_positions_bytes;
    use crate::gtfs_rt::models::BoundingBox;
    use crate::gtfs_rt::proto::{
        FeedEntity, FeedHeader, FeedMessage, Position, TripDescriptor, VehicleDescriptor,
        VehiclePosition,
    };
    use crate::static_db::spatial::{filter_vehicles_in_bbox, vehicles_to_geojson};

    #[test]
    fn test_prost_gtfs_rt_decode_and_spatial_geojson() {
        let msg = FeedMessage {
            header: FeedHeader {
                gtfs_realtime_version: "2.0".to_string(),
                incrementality: Some(0),
                timestamp: Some(1_760_000_000),
            },
            entity: vec![
                FeedEntity {
                    id: "V1".to_string(),
                    is_deleted: Some(false),
                    trip_update: None,
                    vehicle: Some(VehiclePosition {
                        trip: Some(TripDescriptor {
                            trip_id: Some("TRIP_4_6".to_string()),
                            route_id: Some("3040".to_string()),
                            direction_id: Some(0),
                            start_time: None,
                            start_date: None,
                        }),
                        vehicle: Some(VehicleDescriptor {
                            id: Some("BKK_COMBINO_2015".to_string()),
                            label: Some("4-6".to_string()),
                            license_plate: None,
                        }),
                        position: Some(Position {
                            latitude: 47.4740,
                            longitude: 19.0460,
                            bearing: Some(92.5),
                            odometer: None,
                            speed: Some(11.2),
                        }),
                        current_stop_sequence: Some(5),
                        stop_id: Some("F01234".to_string()),
                        timestamp: Some(1_760_000_005),
                    }),
                },
                // Out-of-viewport vehicle (e.g. Debrecen)
                FeedEntity {
                    id: "V2".to_string(),
                    is_deleted: Some(false),
                    trip_update: None,
                    vehicle: Some(VehiclePosition {
                        trip: None,
                        vehicle: Some(VehicleDescriptor {
                            id: Some("OUTSIDE".to_string()),
                            label: Some("IC".to_string()),
                            license_plate: None,
                        }),
                        position: Some(Position {
                            latitude: 47.5316,
                            longitude: 21.6273,
                            bearing: Some(180.0),
                            odometer: None,
                            speed: None,
                        }),
                        current_stop_sequence: None,
                        stop_id: None,
                        timestamp: None,
                    }),
                },
            ],
        };

        let mut buf = Vec::new();
        msg.encode(&mut buf).expect("encode GTFS-RT");

        let mut delays = HashMap::new();
        delays.insert("BKK:TRIP_4_6".to_string(), 180); // 3 min delay -> minor_delay (yellow)

        let decoded =
            decode_bkk_vehicle_positions_bytes(&buf, &delays, None).expect("decode GTFS-RT");
        assert_eq!(decoded.len(), 2);

        let budapest_bbox = BoundingBox {
            min_lat: 47.35,
            min_lon: 18.90,
            max_lat: 47.62,
            max_lon: 19.35,
        };
        let in_view = filter_vehicles_in_bbox(&decoded, budapest_bbox);
        assert_eq!(in_view.len(), 1);
        assert_eq!(in_view[0].id, "BKK:BKK_COMBINO_2015");
        assert_eq!(in_view[0].delay_seconds, 180);

        let geojson = vehicles_to_geojson(&in_view);
        assert!(geojson.contains("\"delay_bucket\":\"minor_delay\""));
        assert!(geojson.contains("\"line_name\":\"4-6\""));
    }

    #[test]
    fn test_decode_real_bkk_pb() {
        if let Ok(bytes) = std::fs::read("target/debug/sample_vp.pb") {
            let delays = HashMap::new();
            let repo = crate::static_db::repository::StaticTransitRepository::open("../assets/db/transit_static.db").ok();
            let decoded = decode_bkk_vehicle_positions_bytes(&bytes, &delays, repo.as_ref());
            match decoded {
                Ok(vehicles) => {
                    println!("Successfully decoded {} real BKK vehicles!", vehicles.len());
                    let mut type_counts = HashMap::new();
                    for v in &vehicles {
                        *type_counts.entry(v.vehicle_type.clone()).or_insert(0) += 1;
                    }
                    println!("Vehicle type counts with static DB: {:?}", type_counts);
                    let mut op_counts = HashMap::new();
                    for v in &vehicles {
                        *op_counts.entry(v.operator.as_str()).or_insert(0) += 1;
                    }
                    println!("Operator counts: {:?}", op_counts);
                    for v in vehicles.iter().filter(|v| v.operator == crate::gtfs_rt::models::Operator::MAV).take(10) {
                        println!("  MÁV Train: id={}, line={}, dest={}, trip={:?}", v.id, v.line_name, v.destination, v.trip_id);
                    }
                    let empty_dest_count = vehicles.iter().filter(|v| v.destination.is_empty()).count();
                    println!("Vehicles with empty destination: {} / {}", empty_dest_count, vehicles.len());
                    assert!(!vehicles.is_empty(), "Vehicle list should not be empty");
                }
                Err(e) => {
                    panic!("Failed to decode real BKK protobuf: {:?}", e);
                }
            }
        }
    }

    #[test]
    fn test_departure_board_query() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let client = reqwest::Client::new();
            let url = "https://go.bkk.hu/api/query/v1/ws/gtfs-rt/full/TripUpdates.pb?key=b4beebb5-1ecb-45fd-a83d-3374edb83a2b";
            if let Ok(resp) = client.get(url).send().await {
                if let Ok(bytes) = resp.bytes().await {
                    use prost::Message;
                    let feed = crate::gtfs_rt::proto::FeedMessage::decode(bytes.as_ref()).unwrap();
                    println!("TripUpdates entities: {}", feed.entity.len());
                    for ent in feed.entity.iter().take(10) {
                        if let Some(ref tu) = ent.trip_update {
                            println!("  TU trip={:?}, route={:?}, stops={}", tu.trip.trip_id, tu.trip.route_id, tu.stop_time_update.len());
                            if let Some(first_stu) = tu.stop_time_update.first() {
                                println!("    first stop_id={:?}, seq={:?}, dep={:?}, arr={:?}", first_stu.stop_id, first_stu.stop_sequence, first_stu.departure, first_stu.arrival);
                            }
                        }
                    }
                    // Check if any MÁV train is in TripUpdates
                    let mav_tu: Vec<_> = feed.entity.iter().filter(|e| {
                        e.trip_update.as_ref().and_then(|t| t.trip.route_id.as_deref()).map(|r| r == "IC" || r == "S10" || r == "G60").unwrap_or(false)
                    }).collect();
                    println!("MÁV TripUpdates count (IC/S10/G60): {}", mav_tu.len());
                    if let Some(m) = mav_tu.first() {
                        let tu = m.trip_update.as_ref().unwrap();
                        println!("  Sample MÁV TU: trip={:?}, route={:?}, stops={}", tu.trip.trip_id, tu.trip.route_id, tu.stop_time_update.len());
                        for stu in tu.stop_time_update.iter().take(5) {
                            println!("    stop_id={:?}, seq={:?}, dep={:?}, arr={:?}", stu.stop_id, stu.stop_sequence, stu.departure, stu.arrival);
                        }
                    }
                }
            }
        });
    }
}
