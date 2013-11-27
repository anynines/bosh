require 'tempfile'
require 'bosh/director/rendered_templates_writer'
require 'bosh/director/compressed_rendered_job_templates'

module Bosh::Director
  class RenderedJobTemplatesPersister
    def initialize(blobstore)
      @blobstore = blobstore
    end

    def persist(instance, rendered_job_templates)
      instance_archives = Models::RenderedTemplatesArchive.filter(instance: instance.model)
      current_archive = instance_archives.reverse_order(:created_at).first

      if !current_archive || current_archive.content_sha1 != instance.configuration_hash
        persist_without_checking(instance, rendered_job_templates)
      end
    end

    def persist_without_checking(instance, rendered_job_templates)
      file = Tempfile.new('compressed-rendered-job-templates')

      compressed_archive = CompressedRenderedJobTemplates.new(file.path)
      compressed_archive.write(rendered_job_templates)

      blobstore_id = @blobstore.create(compressed_archive.contents)

      instance.model.add_rendered_templates_archive(
        blobstore_id: blobstore_id,
        sha1: compressed_archive.sha1,
        content_sha1: instance.configuration_hash,
        created_at: Time.now,
      )
    ensure
      file.close!
    end
  end
end
