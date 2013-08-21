# Connect to the database, use DATABASE_URL if it exists, otherwise use a local
# database -- which you'll need to set up yourself.
DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/contributor")
DataMapper::Model.raise_on_save_failure = true

class Contributor
  include DataMapper::Resource
  property :id, Serial
  property :fullname, String, :length => 255
  property :email, String, :length => 255
  property :address, Text
  property :confirmation_code, String
  property :date_invited, Date
  property :date_accepted, Date

  validates_presence_of :fullname
  validates_presence_of :email
  validates_uniqueness_of :email

end

DataMapper.finalize
DataMapper.auto_upgrade!