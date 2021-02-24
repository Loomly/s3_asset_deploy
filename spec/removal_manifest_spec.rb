require "spec_helper"

RSpec.describe S3AssetDeploy::RemovalManifest do
  subject { described_class.new("test-bucket" ) }

  let(:s3_client) do
    Class.new do
      def initialize(&block)
        @get_object = block
      end

      def put_object(*args)
      end

      def get_object(*args)
        OpenStruct.new(
          body: StringIO.new((@get_object ? @get_object.call(*args) : {}).to_json)
        )
      end
    end
  end

  let(:s3_client_instance) { s3_client.new }

  before { allow_any_instance_of(S3AssetDeploy::RemovalManifest).to receive(:s3) { s3_client_instance } }

  describe "#changed?" do
    let(:s3_client_instance) do
      s3_client.new do
        {
          "assets/file-2-34567.jpg" => (Time.now - 172801).utc.iso8601,
          "assets/file-3-9876666.jpg" => (Time.now - 172799).utc.iso8601
        }
      end
    end

    it "is false after initializing" do
      expect(subject.changed?).to eq(false)
    end

    it "is true after setting an attribute" do
      expect(subject.changed?).to eq(false)
      subject.load
      expect(subject.changed?).to eq(false)
      subject["myfile"] = Time.now.utc.iso8601
      expect(subject.changed?).to eq(true)
    end

    it "is true after deleting an attribute" do
      expect(subject.changed?).to eq(false)
      subject.load
      expect(subject.changed?).to eq(false)
      subject.delete("assets/file-2-34567.jpg")
      expect(subject.changed?).to eq(true)
    end

    it "is false after saving" do
      expect(subject.changed?).to eq(false)
      subject.load
      expect(subject.changed?).to eq(false)
      subject.delete("assets/file-2-34567.jpg")
      expect(subject.changed?).to eq(true)
      subject.save
      expect(subject.changed?).to eq(false)
    end
  end

  describe "#save" do
    it "does not make put_object request to S3 when manifest has not changed" do
      subject.load
      expect(s3_client_instance).to_not receive(:put_object)
      expect(subject.save)
    end

    it "does makes put_object request to S3 when manifest has changed" do
      subject.load
      subject["myfile"] = Time.now.utc.iso8601
      expect(s3_client_instance).to receive(:put_object)
      expect(subject.save)
    end
  end

  describe "#load"  do
    let(:s3_client_instance) do
      s3_client.new do
        {
          "assets/file-2-34567.jpg" => (Time.now - 172801).utc.iso8601,
          "assets/file-3-9876666.jpg" => (Time.now - 172799).utc.iso8601
        }
      end
    end

    it "loads manifest" do
      Timecop.freeze(Time.now) do
        expect(subject.loaded?).to eq(false)
        expect(subject.to_h).to eq({})
        expect(subject.keys).to eq([])
        subject.load
        expect(subject.loaded?).to eq(true)
        expect(subject.to_h).to eq({
          "assets/file-2-34567.jpg" => (Time.now - 172801).utc.iso8601,
          "assets/file-3-9876666.jpg" => (Time.now - 172799).utc.iso8601
        })
        expect(subject.keys).to eq([
          "assets/file-2-34567.jpg",
          "assets/file-3-9876666.jpg"
        ])
      end
    end

    it "won't refetch after initial load" do
      subject.load
      subject["my-file"] = Time.now.utc.iso8601
      subject.load
      expect(subject.keys).to contain_exactly(
        "assets/file-2-34567.jpg",
        "assets/file-3-9876666.jpg",
        "my-file"
      )
    end

    context "with no manifest in S3 bucket" do
      let(:s3_client_instance) do
        s3_client.new do
          raise Aws::S3::Errors::NoSuchKey.new(nil, nil)
        end
      end

      it "initializes manfiest to empty hash when no manifest in S3 bucket" do
        subject.load
        expect(subject.to_h).to eq({})
        expect(subject.loaded?).to eq(true)
      end
    end
  end
end
