//! Native `prost` wire definitions for the official GTFS-Realtime v2.0 specification
//! (`transit_realtime`), eliminating the external `protoc` binary requirement on Windows/Android.

use prost::Message;

#[derive(Clone, PartialEq, Message)]
pub struct FeedMessage {
    #[prost(message, required, tag = "1")]
    pub header: FeedHeader,
    #[prost(message, repeated, tag = "2")]
    pub entity: Vec<FeedEntity>,
}

#[derive(Clone, PartialEq, Message)]
pub struct FeedHeader {
    #[prost(string, required, tag = "1")]
    pub gtfs_realtime_version: String,
    #[prost(enumeration = "feed_header::Incrementality", optional, tag = "2", default = "FullDataset")]
    pub incrementality: Option<i32>,
    #[prost(uint64, optional, tag = "3")]
    pub timestamp: Option<u64>,
}

pub mod feed_header {
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, prost::Enumeration)]
    #[repr(i32)]
    pub enum Incrementality {
        FullDataset = 0,
        Differential = 1,
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct FeedEntity {
    #[prost(string, required, tag = "1")]
    pub id: String,
    #[prost(bool, optional, tag = "2", default = "false")]
    pub is_deleted: Option<bool>,
    #[prost(message, optional, tag = "3")]
    pub trip_update: Option<TripUpdate>,
    #[prost(message, optional, tag = "4")]
    pub vehicle: Option<VehiclePosition>,
}

#[derive(Clone, PartialEq, Message)]
pub struct TripUpdate {
    #[prost(message, required, tag = "1")]
    pub trip: TripDescriptor,
    #[prost(message, optional, tag = "3")]
    pub vehicle: Option<VehicleDescriptor>,
    #[prost(message, repeated, tag = "2")]
    pub stop_time_update: Vec<trip_update::StopTimeUpdate>,
    #[prost(uint64, optional, tag = "4")]
    pub timestamp: Option<u64>,
    #[prost(int32, optional, tag = "5")]
    pub delay: Option<i32>,
}

pub mod trip_update {
    use prost::Message;

    #[derive(Clone, PartialEq, Message)]
    pub struct StopTimeEvent {
        #[prost(int32, optional, tag = "1")]
        pub delay: Option<i32>,
        #[prost(int64, optional, tag = "2")]
        pub time: Option<i64>,
        #[prost(int32, optional, tag = "3")]
        pub uncertainty: Option<i32>,
    }

    #[derive(Clone, PartialEq, Message)]
    pub struct StopTimeUpdate {
        #[prost(uint32, optional, tag = "1")]
        pub stop_sequence: Option<u32>,
        #[prost(string, optional, tag = "4")]
        pub stop_id: Option<String>,
        #[prost(message, optional, tag = "2")]
        pub arrival: Option<StopTimeEvent>,
        #[prost(message, optional, tag = "3")]
        pub departure: Option<StopTimeEvent>,
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct VehiclePosition {
    #[prost(message, optional, tag = "1")]
    pub trip: Option<TripDescriptor>,
    #[prost(message, optional, tag = "8")]
    pub vehicle: Option<VehicleDescriptor>,
    #[prost(message, optional, tag = "2")]
    pub position: Option<Position>,
    #[prost(uint32, optional, tag = "3")]
    pub current_stop_sequence: Option<u32>,
    #[prost(string, optional, tag = "7")]
    pub stop_id: Option<String>,
    #[prost(uint64, optional, tag = "5")]
    pub timestamp: Option<u64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Position {
    #[prost(float, required, tag = "1")]
    pub latitude: f32,
    #[prost(float, required, tag = "2")]
    pub longitude: f32,
    #[prost(float, optional, tag = "3")]
    pub bearing: Option<f32>,
    #[prost(double, optional, tag = "4")]
    pub odometer: Option<f64>,
    #[prost(float, optional, tag = "5")]
    pub speed: Option<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct TripDescriptor {
    #[prost(string, optional, tag = "1")]
    pub trip_id: Option<String>,
    #[prost(string, optional, tag = "5")]
    pub route_id: Option<String>,
    #[prost(uint32, optional, tag = "6")]
    pub direction_id: Option<u32>,
    #[prost(string, optional, tag = "2")]
    pub start_time: Option<String>,
    #[prost(string, optional, tag = "3")]
    pub start_date: Option<String>,
}

#[derive(Clone, PartialEq, Message)]
pub struct VehicleDescriptor {
    #[prost(string, optional, tag = "1")]
    pub id: Option<String>,
    #[prost(string, optional, tag = "2")]
    pub label: Option<String>,
    #[prost(string, optional, tag = "3")]
    pub license_plate: Option<String>,
}
