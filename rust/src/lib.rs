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
            let decoded = decode_bkk_vehicle_positions_bytes(&bytes, &delays, None);
            match decoded {
                Ok(vehicles) => {
                    println!("Successfully decoded {} real BKK vehicles!", vehicles.len());
                    assert!(!vehicles.is_empty(), "Vehicle list should not be empty");
                    println!("Sample vehicle: {:?}", vehicles[0]);
                }
                Err(e) => {
                    panic!("Failed to decode real BKK protobuf: {:?}", e);
                }
            }
        }
    }
}
